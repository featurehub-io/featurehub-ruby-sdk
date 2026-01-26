# frozen_string_literal: true

module FeatureHub
  module Sdk
    # represents an intercepted value
    class InterceptorValue
      def initialize(val)
        @val = val
      end

      def cast(expected_type)
        return @val if expected_type.nil? || @val.nil?

        case expected_type
        when "BOOLEAN"
          @val.to_s.downcase.strip == "true"
        when "NUMBER"
          @val.to_s.to_f
        else
          @val.to_s
        end
      end
    end

    # Holds the pattern for a value based interceptor, which could come from a file, or whatever
    # they are not typed
    class ValueInterceptor
      def intercepted_value(feature_key); end
    end

    # An example of a value interceptor that uses environment variables
    class EnvironmentInterceptor < ValueInterceptor
      def initialize
        super()
        @enabled = ENV.fetch("FEATUREHUB_OVERRIDE_FEATURES", "false") == "true"
      end

      def intercepted_value(feature_key)
        if @enabled
          found = ENV.fetch("FEATUREHUB_#{sanitize_feature_name(feature_key.to_s)}", nil)
          return InterceptorValue.new(found) unless found.nil?
        end

        nil
      end

      private

      def sanitize_feature_name(key)
        key.tr(" ", "_")
      end
    end
  end
end
