# frozen_string_literal: true

module FeatureHub
  module Sdk
    # represents a raw rollout strategy inside a feature
    class RolloutStrategy
      def initialize(strategy)
        @strategy = strategy
      end
    end
  end
end
