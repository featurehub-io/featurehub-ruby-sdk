# frozen_string_literal: true

require "json"
require "concurrent-ruby"
require_relative "session_store_helpers"

module FeatureHub
  module Sdk
    # Optional configuration for RedisSessionStore.
    class RedisSessionStoreOptions
      attr_reader :prefix, :backoff_timeout, :retry_update_count, :refresh_timeout, :logger, :db

      def initialize(opts = nil)
        opts ||= {}
        @prefix = opts[:prefix] || "featurehub"
        @backoff_timeout = opts[:backoff_timeout] || 500
        @retry_update_count = opts[:retry_update_count] || 10
        @refresh_timeout = opts[:refresh_timeout] || 300
        @logger = opts[:logger]
        @db = opts[:db] || 0
      end
    end

    # Persists feature values from a FeatureHubRepository in Redis so they survive
    # process restarts and are shared across multiple processes.
    #
    # Uses SHA256-based change detection and Redis WATCH/MULTI/EXEC for multi-process safety.
    #
    # WARNING: Do not use with server-evaluated features. Each server-evaluated context
    # sends different resolved values; storing them in a shared Redis key will cause
    # processes to overwrite each other's feature states.
    #
    # On initialization the store reads any previously saved features from Redis and
    # replays them into the repository. A periodic timer re-reads the SHA key so that
    # updates published by other processes are picked up automatically.
    class RedisSessionStore < RawUpdateFeatureListener
      include SessionStoreHelpers

      SOURCE = "redis-store"

      # @param connection_or_client [String, Array, Object] Redis URL, list of cluster URLs,
      #   or an existing Redis client
      # @param config [FeatureHubConfig] SDK config (provides repository and environment_id)
      # @param opts [RedisSessionStoreOptions, Hash, nil] optional configuration
      def initialize(connection_or_client, config, opts = nil)
        super()

        options = opts.is_a?(RedisSessionStoreOptions) ? opts : RedisSessionStoreOptions.new(opts)

        @repository = config.repository
        @environment_id = config.environment_id
        @prefix = options.prefix
        @backoff_timeout = options.backoff_timeout
        @retry_update_count = options.retry_update_count
        @refresh_timeout = options.refresh_timeout
        @internal_sha = nil
        @mutex = Mutex.new
        @task = nil
        @logger = options.logger

        return unless redis_available?

        @redis = if connection_or_client.is_a?(String)
                   Redis.new(url: connection_or_client, db: options.db)
                 else
                   connection_or_client
                 end

        config.register_raw_update_listener(self)

        @logger&.debug("[featurehubsdk] started redis store")
        Concurrent::Future.execute { load_from_redis }
        start_timer
      end

      def process_updates(features, source)
        return if source == SOURCE || !redis_available?

        incoming_sha = calculate_sha(features)
        return if incoming_sha == @redis.get(sha_key)

        perform_store_with_retry do |redis_features|
          has_newer = features.any? do |f|
            existing = redis_features.find { |rf| rf["id"] == f["id"] }
            existing.nil? || version_of(f) > version_of(existing)
          end
          has_newer ? merge_features(redis_features, features) : nil
        end
      end

      def process_update(feature, source)
        return if source == SOURCE || !redis_available?

        perform_store_with_retry do |redis_features|
          existing = redis_features.find { |f| f["id"] == feature["id"] }
          next nil if existing && version_of(existing) >= version_of(feature)

          merge_features(redis_features, [feature])
        end
      end

      def delete_feature(feature, source)
        return if source == SOURCE || !redis_available? || !feature["id"]

        perform_store_with_retry do |redis_features|
          updated = redis_features.reject { |f| f["id"] == feature["id"] }
          updated.length < redis_features.length ? updated : nil
        end
      end

      def close
        return if @task.nil?

        @task.shutdown
        @task = nil
      end

      private

      def redis_available?
        @redis_available ||= begin
          require "redis"
          true
        rescue LoadError
          false
        end
      end

      def load_from_redis
        sha = @redis.get(sha_key)
        @mutex.synchronize { @internal_sha = sha }

        features = read_features_from_redis
        return if features.empty?

        @logger&.debug("[featurehubsdk] loading #{features.size} feature(s) from redis")
        @repository.notify("features", features, SOURCE)
      end

      def start_timer
        @task = Concurrent::TimerTask.new(execution_interval: @refresh_timeout, run_now: false) do
          check_for_updates
        end
        @task.execute
      end

      def check_for_updates
        return unless redis_available?

        current_sha = @redis.get(sha_key)
        stored_sha = @mutex.synchronize { @internal_sha }
        return if current_sha == stored_sha

        features = read_features_from_redis
        @logger&.debug("[featurehubsdk] detected redis change, reloading #{features.size} feature(s)")
        @repository.notify("features", features, SOURCE)
        @mutex.synchronize { @internal_sha = current_sha }
      end

      # Computes what to write by yielding the current Redis features to the block.
      # The block returns the new features array to store, or nil to abort.
      # Uses WATCH/MULTI/EXEC with retry to handle multi-process contention.
      def perform_store_with_retry
        attempt = 0
        while attempt < @retry_update_count
          redis_features = read_features_from_redis
          new_features = yield(redis_features)
          return if new_features.nil?

          new_sha = calculate_sha(new_features)
          current_internal = @mutex.synchronize { @internal_sha }
          return if new_sha == current_internal

          current_sha = @redis.get(sha_key)

          if current_sha != current_internal
            # Another process updated Redis — reload and recheck on next attempt
            sleep(@backoff_timeout / 1000.0) unless attempt == @retry_update_count - 1
            attempt += 1
            next
          end

          stored = attempt_atomic_write(current_internal, new_sha, new_features)

          if stored
            @mutex.synchronize { @internal_sha = new_sha }
            return
          end

          sleep(@backoff_timeout / 1000.0) unless attempt == @retry_update_count - 1
          attempt += 1
        end

        @logger&.warn("[featurehubsdk] failed to update redis after #{@retry_update_count} retries")
      end

      # Uses WATCH + MULTI/EXEC to atomically update both keys only if sha_key has not
      # been modified since we read it. Returns true if the transaction committed.
      def attempt_atomic_write(current_internal, new_sha, new_features)
        @redis.watch(sha_key)
        current = @redis.get(sha_key)

        unless current == current_internal
          @redis.unwatch
          return false
        end

        result = @redis.multi do |tx|
          tx.set(features_key, new_features.to_json)
          tx.set(sha_key, new_sha)
        end

        result.is_a?(Array)
      end

      def read_features_from_redis
        json = @redis.get(features_key)
        return [] unless json

        JSON.parse(json)
      rescue JSON::ParserError
        []
      end
    end
  end
end
