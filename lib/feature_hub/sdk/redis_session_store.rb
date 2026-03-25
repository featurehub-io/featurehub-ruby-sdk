# frozen_string_literal: true

require "json"
require "concurrent-ruby"

module FeatureHub
  module Sdk
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
    #
    # Options (symbol keys):
    #   :namespace  - Redis db index (default: 0)
    #   :prefix     - key prefix for all Redis keys (default: "featurehub")
    #   :timeout    - seconds between periodic reloads (default: 30)
    class RedisSessionStore < RawUpdateFeatureListener
      SOURCE = "redis-store"

      def initialize(connection_string, repository, opts = nil, logger = nil)
        super()

        opts ||= {}
        @repository = repository
        @prefix = opts[:prefix] || "featurehub"
        @timeout = opts[:timeout] || 30
        @namespace = opts[:namespace] || 0
        @password = opts[:password]
        @logger = logger || Sdk.default_logger
        @task = nil

        return unless redis_available?

        redis_opts = { url: connection_string, db: @namespace }
        redis_opts[:password] = @password if @password
        @redis = Redis.new(**redis_opts)
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

        return if features.empty?

        @logger.debug("[featurehubsdk] loading #{features.size} feature(s) from redis")
        @repository.notify("features", features, SOURCE)
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
