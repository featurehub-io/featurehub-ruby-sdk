# frozen_string_literal: true

require "yaml"
require "json"
require "securerandom"

module FeatureHub
  module Sdk
    # Reads feature flags from a local YAML file and loads them into a FeatureHubRepository,
    # allowing the SDK to operate without a FeatureHub Edge server.
    # Implements RawUpdateFeatureListener but silently ignores all incoming update callbacks —
    # the file is the single source of truth and is read exactly once at initialization.
    #
    # Expected YAML format (same as LocalYamlValueInterceptor):
    #   flagValues:
    #     MY_FLAG: true
    #     MY_STRING: "hello"
    #     MY_NUMBER: 42
    class LocalYamlStore < RawUpdateFeatureListener
      SOURCE = "local-yaml"

      def initialize(repository, filename = nil)
        super()
        @environment_id = SecureRandom.uuid
        yaml_file = filename || ENV.fetch("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml")
        features = load_features(yaml_file)
        repository.notify("features", features, SOURCE) if features
      end

      private

      def load_features(yaml_file)
        return nil unless File.exist?(yaml_file)

        data = YAML.safe_load(File.read(yaml_file))
        flag_values = data&.fetch("flagValues", {}) || {}
        flag_values.map { |key, value| build_feature_state(key.to_s, value) }
      rescue StandardError
        nil
      end

      def build_feature_state(key, value)
        {
          "id" => SecureRandom.uuid,
          "key" => key,
          "l" => false,
          "version" => 1,
          "type" => feature_type(value),
          "value" => cast_value(value),
          "environmentId" => @environment_id
        }
      end

      def feature_type(value)
        case value
        when true, false then FeatureValueType::BOOLEAN
        when Integer, Float then FeatureValueType::NUMBER
        when String then FeatureValueType::STRING
        else FeatureValueType::JSON
        end
      end

      def cast_value(value)
        return value.to_f if value.is_a?(Integer) || value.is_a?(Float)
        return value.to_json if value.is_a?(Hash) || value.is_a?(Array)

        value
      end
    end
  end
end
