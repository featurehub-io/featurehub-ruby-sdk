# frozen_string_literal: true

require "concurrent-ruby"

module FeatureHub
  module Sdk
    # the core implementation of a feature repository
    class FeatureHubRepository < InternalFeatureRepository
      attr_reader :features

      def initialize(apply_features = nil)
        super()
        @strategy_matcher = apply_features || FeatureHub::Sdk::Impl::ApplyFeature.new
        @interceptors = []
        @raw_listeners = []
        @features = {}
        @ready = false
      end

      def apply(strategies, key, feature_id, context)
        @strategy_matcher.apply(strategies, key, feature_id, context)
      end

      def notify(status, data, source = "unknown")
        return unless status

        if status.to_sym == :failed
          @ready = false
          return
        end

        return if data.nil?

        case status.to_sym
        when :features
          update_features(data)
          @ready = true
          notify_raw_listeners_async { |l| l.process_updates(data, source) }
        when :feature
          return if data.nil? || data["key"].nil?
          update_feature(data)
          @ready = true
          notify_raw_listeners_async { |l| l.process_update(data, source) }
        when :delete_feature
          return unless data && data["key"]

          delete_feature(data)
          notify_raw_listeners_async { |l| l.delete_feature(data, source) }
        end
      end

      def feature(key)
        sym_key = key.to_sym
        @features[sym_key] || make_feature_holder(sym_key)
      end

      def register_interceptor(interceptor)
        @interceptors.push(interceptor)
      end

      def register_raw_update_listener(listener)
        @raw_listeners.push(listener)
      end

      def find_interceptor(feature_key, feature_state = nil)
        @interceptors.each do |interceptor|
          matched, value = interceptor.intercepted_value(feature_key, self, feature_state)
          return [true, value] if matched
        end
        [false, nil]
      end

      def close
        @interceptors.each(&:close)
        @raw_listeners.each(&:close)
      end

      def ready?
        @ready
      end

      def not_ready!
        @ready = false
      end

      def extract_feature_state
        @features.values
                 .filter(&:exists?)
                 .map(&:feature_state)
      end

      private

      def delete_feature(data)
        feat = @features[data["key"].to_sym]

        feat&.update_feature_state(nil)
      end

      def make_feature_holder(key)
        fs = FeatureHub::Sdk::FeatureStateHolder.new(key, self)
        @features[key.to_sym] = fs
        fs
      end

      def update_features(data)
        data.each do |feature|
          update_feature(feature)
        end
      end

      def notify_raw_listeners_async
        return if @raw_listeners.empty?

        listeners = @raw_listeners.dup
        Concurrent::Future.execute { listeners.each { |l| yield l } }
      end

      def update_feature(feature_state)
        key = feature_state["key"].to_sym
        holder = @features[key]
        if !holder
          @features[key] = FeatureHub::Sdk::FeatureStateHolder.new(key, self, feature_state)
          return
        elsif feature_state["version"] < holder.version
          return
        elsif feature_state["version"] == holder.version && feature_state["value"] == holder.value # rubocop:disable Lint/DuplicateBranch
          return
        end

        holder.update_feature_state(feature_state)
      end
    end
  end
end
