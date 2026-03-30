# frozen_string_literal: true

require "json"
require "digest"
require "concurrent-ruby"

module FeatureHub
  module Sdk
    # Optional configuration for MemcacheSessionStore.
    class MemcacheSessionStoreOptions
      attr_reader :prefix, :backoff_timeout, :retry_update_count, :refresh_timeout, :logger

      def initialize(opts = nil)
        opts ||= {}
        @prefix = opts[:prefix] || "featurehub"
        @backoff_timeout = opts[:backoff_timeout] || 500
        @retry_update_count = opts[:retry_update_count] || 10
        @refresh_timeout = opts[:refresh_timeout] || 300
        @logger = opts[:logger]
      end
    end

    # Persists feature values from a FeatureHubRepository in Memcache so they survive
    # process restarts and are shared across multiple processes.
    #
    # Uses SHA256-based change detection and compare-and-set for multi-process safety.
    #
    # WARNING: Do not use with server-evaluated features. Each server-evaluated context
    # sends different resolved values; storing them in a shared Memcache key will cause
    # processes to overwrite each other's feature states.
    #
    # On initialization the store reads any previously saved features from Memcache and
    # replays them into the repository. A periodic timer re-reads the SHA key so that
    # updates published by other processes are picked up automatically.
    class MemcacheSessionStore < RawUpdateFeatureListener
      SOURCE = "memcache-store"

      # @param connection_or_client [String, Dalli::Client] Memcache connection string or existing client
      # @param config [FeatureHubConfig] SDK config (provides repository and environment_id)
      # @param opts [MemcacheSessionStoreOptions, Hash, nil] optional configuration
      def initialize(connection_or_client, config, opts = nil)
        super()

        options = opts.is_a?(MemcacheSessionStoreOptions) ? opts : MemcacheSessionStoreOptions.new(opts)

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

        return unless dalli_available?

        @dalli = if connection_or_client.is_a?(String)
                   Dalli::Client.new(connection_or_client)
                 else
                   connection_or_client
                 end

        load_from_memcache
        start_timer
      end

      def process_updates(features, source)
        return if source == SOURCE || !dalli_available?

        incoming_sha = calculate_sha(features)
        return if incoming_sha == @dalli.get(sha_key)

        perform_store_with_retry do |memcache_features|
          has_newer = features.any? do |f|
            existing = memcache_features.find { |mf| mf["id"] == f["id"] }
            existing.nil? || version_of(f) > version_of(existing)
          end
          has_newer ? merge_features(memcache_features, features) : nil
        end
      end

      def process_update(feature, source)
        return if source == SOURCE || !dalli_available?

        perform_store_with_retry do |memcache_features|
          existing = memcache_features.find { |f| f["id"] == feature["id"] }
          next nil if existing && version_of(existing) >= version_of(feature)

          merge_features(memcache_features, [feature])
        end
      end

      def delete_feature(feature, source)
        return if source == SOURCE || !dalli_available? || !feature["id"]

        perform_store_with_retry do |memcache_features|
          updated = memcache_features.reject { |f| f["id"] == feature["id"] }
          updated.length < memcache_features.length ? updated : nil
        end
      end

      def close
        return if @task.nil?

        @task.shutdown
        @task = nil
      end

      private

      def dalli_available?
        @dalli_available ||= begin
          require "dalli"
          true
        rescue LoadError
          false
        end
      end

      def load_from_memcache
        sha = @dalli.get(sha_key)
        @mutex.synchronize { @internal_sha = sha }

        features = read_features_from_memcache
        return if features.empty?

        @logger&.debug("[featurehubsdk] loading #{features.size} feature(s) from memcache")
        @repository.notify("features", features, SOURCE)
      end

      def start_timer
        @task = Concurrent::TimerTask.new(execution_interval: @refresh_timeout, run_now: false) do
          check_for_updates
        end
        @task.execute
      end

      def check_for_updates
        return unless dalli_available?

        current_sha = @dalli.get(sha_key)
        stored_sha = @mutex.synchronize { @internal_sha }
        return if current_sha == stored_sha

        features = read_features_from_memcache
        @logger&.debug("[featurehubsdk] detected memcache change, reloading #{features.size} feature(s)")
        @repository.notify("features", features, SOURCE)
        @mutex.synchronize { @internal_sha = current_sha }
      end

      # Computes what to write by yielding the current memcache features to the block.
      # The block returns the new features array to store, or nil to abort.
      # Uses compare-and-set with retry to handle multi-process contention.
      def perform_store_with_retry
        @retry_update_count.times do |attempt|
          memcache_features = read_features_from_memcache
          new_features = yield(memcache_features)
          return if new_features.nil?

          new_sha = calculate_sha(new_features)
          current_internal = @mutex.synchronize { @internal_sha }
          return if new_sha == current_internal

          current_sha = @dalli.get(sha_key)

          unless current_sha == current_internal
            # Another process updated memcache — reload and recheck on next attempt
            sleep(@backoff_timeout / 1000.0) unless attempt == @retry_update_count - 1
            next
          end

          stored = attempt_atomic_write(current_sha, new_sha, current_internal)

          if stored
            @dalli.set(features_key, new_features.to_json)
            @mutex.synchronize { @internal_sha = new_sha }
            return
          end

          sleep(@backoff_timeout / 1000.0) unless attempt == @retry_update_count - 1
        end

        @logger&.warn("[featurehubsdk] failed to update memcache after #{@retry_update_count} retries")
      end

      def attempt_atomic_write(current_sha, new_sha, current_internal)
        if current_sha.nil?
          !!@dalli.add(sha_key, new_sha)
        else
          stored = false
          @dalli.cas(sha_key) do |current|
            if current == current_internal
              stored = true
              new_sha
            else
              current # write back same value — harmless no-op if CAS token still valid
            end
          end
          stored
        end
      end

      def read_features_from_memcache
        json = @dalli.get(features_key)
        return [] unless json

        JSON.parse(json)
      rescue JSON::ParserError
        []
      end

      def merge_features(base, updates)
        result = base.dup
        updates.each do |update|
          idx = result.find_index { |f| f["id"] == update["id"] }
          if idx
            result[idx] = update if version_of(update) > version_of(result[idx])
          else
            result << update
          end
        end
        result
      end

      def calculate_sha(features)
        parts = features.map { |f| "#{f["id"]}:#{version_of(f)}" }.join("|")
        Digest::SHA256.hexdigest(parts)
      end

      def version_of(feature)
        (feature["version"] || 0).to_i
      end

      def features_key
        "#{@prefix}_#{@environment_id}"
      end

      def sha_key
        "#{@prefix}_#{@environment_id}_sha"
      end
    end
  end
end
