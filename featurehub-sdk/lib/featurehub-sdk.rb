# frozen_string_literal: true

require_relative "feature_hub/sdk/apply_features"
require_relative "feature_hub/sdk/version"
require_relative "feature_hub/sdk/context"
require_relative "feature_hub/sdk/feature_hub_config"
require_relative "feature_hub/sdk/internal_feature_repository"
require_relative "feature_hub/sdk/feature_repository"
require_relative "feature_hub/sdk/feature_state"
require_relative "feature_hub/sdk/interceptors"
require_relative "feature_hub/sdk/strategies"
require_relative "feature_hub/sdk/strategy_attributes"
require_relative "feature_hub/sdk/strategy_wrappers"
require_relative "feature_hub/sdk/poll_edge_service"

puts("loaded sdk")

module FeatureHub
  module Sdk
    class Error < StandardError; end
    # Your code goes here...
  end
end
