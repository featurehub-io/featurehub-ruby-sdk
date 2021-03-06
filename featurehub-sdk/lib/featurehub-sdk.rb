# frozen_string_literal: true

require_relative "feature_hub/sdk/impl/rollout_holders"
require_relative "feature_hub/sdk/impl/apply_features"
require_relative "feature_hub/sdk/percentage_calc"
require_relative "feature_hub/sdk/impl/murmur3_percentage"
require_relative "feature_hub/sdk/version"
require_relative "feature_hub/sdk/context"
require_relative "feature_hub/sdk/feature_hub_config"
require_relative "feature_hub/sdk/internal_feature_repository"
require_relative "feature_hub/sdk/feature_repository"
require_relative "feature_hub/sdk/feature_state"
require_relative "feature_hub/sdk/interceptors"
require_relative "feature_hub/sdk/strategy_attributes"
require_relative "feature_hub/sdk/impl/strategy_wrappers"
require_relative "feature_hub/sdk/poll_edge_service"
require_relative "feature_hub/sdk/streaming_edge_service"

# the FeatureHub SDK namespace
module FeatureHub
  # the main SDK

  module Sdk
    # classes inside here are intended to be internal details, do not rely on them
    module Impl
    end

    class Error < StandardError; end
  end
end
