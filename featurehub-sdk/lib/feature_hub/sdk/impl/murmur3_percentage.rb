# frozen_string_literal: true

require "murmurhash3"

module FeatureHub
  module Sdk
    module Impl

      # consistent across all platforms murmur percentage calculator
      class Murmur3PercentageCalculator < FeatureHub::Sdk::PercentageCalculator
        MAX_PERCENTAGE = 1_000_000
        SEED = 0

        def determine_client_percentage(percentage_text, feature_id)
          result = MurmurHash3::V32.str_digest(percentage_text + feature_id, SEED).unpack1("L").to_f
          (result / (2**32) * MAX_PERCENTAGE).floor
        end
      end
    end
  end
end
