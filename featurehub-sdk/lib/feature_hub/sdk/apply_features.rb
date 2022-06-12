# frozen_string_literal: true

require "time"

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

    # full mechanism for applying client side evaluation
    class ApplyFeature
      def initialize(percent_calculator = nil, matcher_repository = nil)
        @percentage_calculator = percent_calculator || FeatureHub::Sdk::Murmur3PercentageCalculator.new
        @matcher_repository = matcher_repository || FeatureHub::Sdk::MatcherRegistry.new
      end

      def apply(strategies, _key, feature_value_id, context)
        return Applied.new(false, nil) if context.nil? || strategies.nil? || strategies.empty?

        percentage = nil
        percentage_key = nil
        base_percentage = {}
        default_percentage_key = context.default_percentage_key

        strategies.each do |rsi|
          if (rsi.percentage != 0) && (!default_percentage_key.nil? || rsi.percentage_attributes?)
            new_percentage_key = ApplyFeature.determine_percentage_key(context, rsi)

            base_percentage[new_percentage_key] = 0 if base_percentage[new_percentage_key].nil?

            base_percentage_val = base_percentage[new_percentage_key]

            if percentage.nil? || new_percentage_key != percentage_key
              percentage_key = new_percentage_key
              percentage = @percentage_calculator.determine_client_percentage(percentage_key, feature_value_id)
              use_base_percentage = rsi.attributes? ? 0 : base_percentage_val

              # rubocop:disable Layout/MultilineOperationIndentation
              if percentage <= (use_base_percentage + rsi.percentage) &&
                (!rsi.attributes? || (rsi.attributes? && match_attribute(context, rsi)))
                return Applied.new(true, rsi.value)
              end

              # rubocop:enable Layout/MultilineOperationIndentation

              unless rsi.attributes?
                base_percentage[percentage_key] =
                  base_percentage[percentage_key] + rsi.percentage
              end
            end
          end

          return Applied.new(true, rsi.value) if rsi.percentage.zero? && rsi.attributes? && match_attribute(context,
                                                                                                            rsi)
        end

        Applied.new(false, nil)
      end

      def match_attribute(context, rs_attr)
        rs_attr.attributes.each do |attr|
          supplied_value = context.get_attr(attr.field_name)
          if supplied_value.nil? && attr.field_name.downcase == "now"
            case attr.field_type
            when "DATE"
              supplied_value = Time.new.utc.iso8601[0..9]
            when "DATETIME"
              supplied_value = Time.new.utc.iso8601
            end
          end

          if attr.values.nil? || supplied_value.nil?
            return false unless attr.conditional.equals?

            continue
          end

          return false if attr.values.nil? || supplied_value.nil?

          # this attribute has to match or we failed
          return false unless @matcher_repository.find_matcher(attr).match(supplied_value, attr)
        end

        true
      end

      def self.determine_percentage_key(context, rsi)
        if rsi.percentage_attributes?
          rsi.percentage_attributes.map { |attr| context.get_attr(attr, "<none>") }.join("$")
        else
          context.default_percentage_key
        end
      end
    end
  end
end
