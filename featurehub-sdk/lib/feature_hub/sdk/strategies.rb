# frozen_string_literal: true

module FeatureHub
  module Sdk
    # represents the application of a match, either successfully or not
    class Applied
      attr_reader :matched, :value

      def initialize(matched, value)
        @matched = matched
        @value = value
      end
    end

    class ApplyFeatures
      def apply(strategies, key, feature_id, context)
        Applied.new(false, nil)
      end
    end
  end
end
