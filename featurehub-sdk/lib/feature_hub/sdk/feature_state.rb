# frozen_string_literal: true

module FeatureHub
  module Sdk
    # represents internal state of a feature
    class FeatureState
      attr_reader :key, :internal_feature_state, :encoded_strategies

      def initialize(key, repo, feature_state = nil, parent_state = nil, ctx = nil)
        @key = key.to_sym
        @parent_state = parent_state
        @ctx = ctx
        @repo = repo
        @encoded_strategies = []

        if feature_state
          _set_feature_state(feature_state)
        else
          @internal_feature_state = {}
        end
      end

      def locked?
        fs = feature_state
        exists?(fs) ? fs["l"] : false
      end

      def exists?(top_feature = nil)
        fs = top_feature || feature_state
        !(fs.empty? || fs["l"].nil?)
      end

      def id
        exists? ? @internal_feature_state["id"] : nil
      end

      def feature_type
        fs = feature_state
        exists?(fs) ? fs["type"] : nil
      end

      def with_context(ctx)
        FeatureState.new(@key, @repo, nil, self, ctx)
      end

      def update_feature_state(feature_state)
        _set_feature_state(feature_state)
      end

      def feature_state
        top_feature_state.internal_feature_state
      end

      def value
        get_value(feature_type)
      end

      def version
        fs = feature_state
        exists?(fs) ? fs["version"] : -1
      end

      def string
        get_value("STRING")
      end

      def number
        get_value("NUMBER")
      end

      def raw_json
        get_value("JSON")
      end

      def boolean
        get_value("BOOLEAN")
      end

      def flag
        boolean
      end

      def enabled?
        boolean == true
      end

      def set?
        value != nil?
      end

      def top_feature_state
        return @parent_state&.top_feature_state if @parent_state

        self
      end

      private

      def _feature_state
        @internal_feature_state
      end

      def _set_feature_state(feature_state)
        @internal_feature_state = feature_state || {}
        found_strategies = feature_state["strategies"] || []
        @encoded_strategies = found_strategies.map { |s| FeatureHub::Sdk::Impl::RolloutStrategy.new(s) }
      end

      def get_value(feature_type)
        unless locked?
          intercept = @repo.find_interceptor(@key)

          return intercept.cast(feature_type) if intercept
        end

        fs = top_feature_state

        state = fs.internal_feature_state

        return nil if state.nil?

        return nil if fs.nil? || (!feature_type.nil? && fs.feature_type != feature_type)

        if @ctx
          matched = @repo.apply(fs.encoded_strategies, @key, fs.id, @ctx)

          return FeatureHub::Sdk::InterceptorValue.new(matched.value).cast(feature_type) if matched.matched
        end

        state["value"]
      end
    end
  end
end
