# frozen_string_literal: true

require "json"
require "concurrent-ruby"

module FeatureHub
  module Sdk
    # Configuration options for RedisSessionStore.
    class RedisSessionStoreOptions
      attr_reader :namespace, :prefix, :timeout

      def initialize(namespace: 0, prefix: "featurehub", timeout: 30 * 60)
        @namespace = namespace
        @prefix = prefix
        @timeout = timeout
      end
    end

    # Persists feature values from a FeatureHubRepository in Redis so they survive
    # process restarts and are shared across multiple processes.
    #
    # WARNING: Do not use with server-evaluated features. Each server-evaluated
    # context sends different resolved values; storing them in a shared Redis key
    # will cause processes to overwrite each other's feature states.
    #
    # On initialization the store checks Redis for previously saved features and
    # replays them into the repository. It then listens for live updates via
    # RawUpdateFeatureListener and writes newer versions back to Redis. A periodic
    # timer re-reads all features from Redis so that updates published by other
    # processes are picked up automatically.
    class RedisSessionStore < RawUpdateFeatureListener
      SOURCE = "redis-store"

      def initialize(connection_string, repository, options = nil)
        super()

        @repository = repository
        opts = options || RedisSessionStoreOptions.new
        @prefix = opts.prefix
        @timeout = opts.timeout
        @namespace = opts.namespace
        @task = nil

        return unless redis_available?

        @redis = Redis.new(url: connection_string, db: @namespace)
        load_from_redis
        start_timer
      end

      def process_updates(features, source)
        return if source == SOURCE || !redis_available?

        features.each { |f| store_feature(f) }
      end

      def process_update(feature, source)
        return if source == SOURCE || !redis_available?

        store_feature(feature)
      end

      def delete_feature(feature, source)
        return if source == SOURCE || !redis_available? || !feature["id"]

        @redis.srem(ids_key, feature["id"])
        @redis.del(feature_key(feature["id"]))
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
        ids = @redis.smembers(ids_key)
        return if ids.empty?

        features = ids.filter_map do |id|
          json = @redis.get(feature_key(id))
          JSON.parse(json) if json
        end

        @repository.notify("features", features, SOURCE) unless features.empty?
      end

      def start_timer
        @task = Concurrent::TimerTask.new(execution_interval: @timeout, run_now: false) do
          load_from_redis
        end
        @task.execute
      end

      def store_feature(feature)
        return unless feature && feature["id"] && feature["key"]

        existing_json = @redis.get(feature_key(feature["id"]))
        if existing_json
          existing = JSON.parse(existing_json)
          return if existing["version"].to_i >= feature["version"].to_i
        end

        @redis.sadd(ids_key, feature["id"])
        @redis.set(feature_key(feature["id"]), feature.to_json)
      end

      def ids_key
        "#{@prefix}_ids"
      end

      def feature_key(id)
        "#{@prefix}_#{id}"
      end
    end
  end
end
