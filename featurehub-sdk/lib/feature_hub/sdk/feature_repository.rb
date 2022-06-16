# frozen_string_literal: true

module FeatureHub
  module Sdk
    # the core implementation of a feature repository
    class FeatureHubRepository < InternalFeatureRepository
      attr_reader :features

      def initialize(apply_features = nil)
        super()
        @strategy_matcher = apply_features || FeatureHub::Sdk::Impl::ApplyFeature.new
        @interceptors = []
        @features = {}
        @ready = false
      end

      def apply(strategies, key, feature_id, context)
        @strategy_matcher.apply(strategies, key, feature_id, context)
      end

      def notify(status, data)
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
        when :feature
          update_feature(data)
          @ready = true
        when :delete_feature
          delete_feature(data)
        end
      end

      def feature(key)
        sym_key = key.to_sym
        @features[sym_key] || make_feature_holder(sym_key)
      end

      def register_interceptor(interceptor)
        @interceptors.push(interceptor)
      end

      def find_interceptor(feature_value)
        @interceptors.find { |interceptor| interceptor.intercepted_value(feature_value) }
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
        return unless data && data["key"]

        feat = @features[data["key"].to_sym]

        feat&.update_feature_state(nil)
      end

      def make_feature_holder(key)
        fs = FeatureHub::Sdk::FeatureState.new(key, self)
        @features[key.to_sym] = fs
        fs
      end

      def update_features(data)
        data.each do |feature|
          update_feature(feature)
        end
      end

      def update_feature(feature_state)
        return if feature_state.nil? || feature_state["key"].nil?

        key = feature_state["key"].to_sym
        holder = @features[key]
        if !holder
          @features[key] = FeatureHub::Sdk::FeatureState.new(key, self, feature_state)
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
