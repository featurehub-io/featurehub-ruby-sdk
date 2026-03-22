# frozen_string_literal: true

require "yaml"
require "json"

module FeatureHub
  module Sdk
    # Reads feature flag overrides from a local YAML file.
    # The file path is read from FEATUREHUB_LOCAL_YAML or defaults to featurehub-features.yaml.
    # Expected format:
    #   flagValues:
    #     MY_FLAG: true
    #     MY_STRING: "hello"
    class LocalYamlValueInterceptor < ValueInterceptor
      def initialize
        super()
        yaml_file = ENV.fetch("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml")
        @flag_values = load_flag_values(yaml_file)
      end

      def intercepted_value(feature_key, _repository, feature_state)
        key = feature_key.to_s
        return [false, nil] unless @flag_values.key?(key)

        value = @flag_values[key]

        if feature_state
          return [false, nil] unless yaml_value_type(value) == feature_state["type"]
        end

        [true, cast_value(value)]
      end

      private

      def load_flag_values(yaml_file)
        return {} unless File.exist?(yaml_file)

        data = YAML.safe_load(File.read(yaml_file))
        data&.fetch("flagValues", {}) || {}
      rescue StandardError
        {}
      end

      def yaml_value_type(value)
        case value
        when true, false
          FeatureValueType::BOOLEAN
        when Integer, Float
          FeatureValueType::NUMBER
        when String
          FeatureValueType::STRING
        else
          FeatureValueType::JSON
        end
      end

      def cast_value(value)
        case value
        when true, false
          value
        when Integer, Float
          value.to_f
        else
          value
        end
      end
    end
  end
end
