# frozen_string_literal: true

require "yaml"
require "json"
require "concurrent-ruby"

module FeatureHub
  module Sdk
    # Reads feature flag overrides from a local YAML file.
    # The file path is read from FEATUREHUB_LOCAL_YAML or defaults to featurehub-features.yaml.
    # Pass watch: true to reload the file automatically when it changes.
    # Expected format:
    #   flagValues:
    #     MY_FLAG: true
    #     MY_STRING: "hello"
    class LocalYamlValueInterceptor < ValueInterceptor
      def initialize(opts = nil)
        super()
        opts ||= {}
        @yaml_file = opts[:filename] || ENV.fetch("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml")
        @logger = opts[:logger]
        @mutex = Mutex.new
        @flag_values = load_flag_values(@yaml_file)
        @logger&.debug("[featurehubsdk] loaded #{@flag_values.size} feature override(s) from #{@yaml_file}")
        @watcher = nil

        return unless opts[:watch]

        @last_mtime = File.exist?(@yaml_file) ? File.mtime(@yaml_file) : nil
        watch_interval = opts[:watch_interval] || 5
        @watcher = Concurrent::TimerTask.new(execution_interval: watch_interval, run_now: false) do
          reload_if_changed
        end
        @watcher.execute
      end

      def intercepted_value(feature_key, _repository, feature_state)
        key = feature_key.to_s
        flag_values = @mutex.synchronize { @flag_values }
        return [false, nil] unless flag_values.key?(key)

        value = flag_values[key]

        return [false, nil] if feature_state && yaml_value_type(value) != feature_state["type"]

        [true, cast_value(value)]
      end

      def close
        return if @watcher.nil?

        @watcher.shutdown
        @watcher = nil
      end

      private

      def reload_if_changed
        return unless File.exist?(@yaml_file)

        current_mtime = File.mtime(@yaml_file)
        return if current_mtime == @last_mtime

        @last_mtime = current_mtime
        new_values = load_flag_values(@yaml_file)
        @logger&.debug("[featurehubsdk] reloaded #{new_values.size} feature override(s) from #{@yaml_file}")
        @mutex.synchronize { @flag_values = new_values }
      end

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
        return value.to_f if value.is_a?(Integer) || value.is_a?(Float)

        value
      end
    end
  end
end
