# frozen_string_literal: true

require 'time'

module FeatureHub
  module Sdk

    # full mechanism for applying client side evaluation
    class ApplyFeature
      def initialize(percent_calculator = nil, matcher_repository = nil)
        @percentage_calculator = percent_calculator || FeatureHub::Sdk::Murmur3PercentageCalculator.new
        @matcher_repository = matcher_repository || FeatureHub::Sdk::MatcherRegistry.new
      end

      def apply(strategies, key, feature_value_id, context)
        if context.nil? || strategies.nil? || strategies.empty?
          return Applied.new(false, nil)
        end

        percentage = nil
        percentage_key = nil
        base_percentage = {}
        default_percentage_key = context.default_percentage_key

        strategies.each do |rsi|
          if rsi.percentage != 0 and (!default_percentage_key.nil? || rsi.percentage_attributes?)
            new_percentage_key = determine_percentage_key(context, rsi)

            if base_percentage[new_percentage_key].nil?
              base_percentage[new_percentage_key] = 0
            end

            base_percentage_val = base_percentage[new_percentage_key]

            if percentage.nil? || new_percentage_key != percentage_key
              percentage_key = new_percentage_key
              percentage = @percentage_calculator.determine_client_percentage(percentage_key, feature_value_id)
              use_base_percentage = rsi.attributes? ? 0 : base_percentage_val

              # rubocop:disable Metrics/BlockNesting
              if percentage <= (use_base_percentage + rsi.percentage)
                if !rsi.attributes? || (rsi.attributes? && match_attribute(context, rsi))
                  return Applied(true, rsi.value)
                end
              end
              # rubocop:enable Metrics/BlockNesting

              unless rsi.attributes?
                base_percentage[percentage_key] = base_percentage[percentage_key] + rsi.percentage
              end
            end
          end

          if rsi.percentage == 0 && rsi.attributes? && match_attribute(context, rsi)
            return Applied(true, rsi.value)
          end
        end

        return Applied(false, nil)
      end

      def match_attribute(context, rs)
        rs.attributes.each do |attr|
          supplied_value = context.get_attr(attr.field_name)
          if supplied_value.nil? && attr.field_name.downcase == 'now'
            if attr.field_type == 'DATE'
              supplied_value = Time.new.utc.iso8601[0..9]
            elsif attr.field_type == 'DATETIME'
              supplied_value = Time.new.utc.iso8601
            end
          end

          if attr.values.nil? || supplied_value.nil?
            unless attr.conditional.equals?
              return false
            end

            continue
          end

          if attr.values.nil? || supplied_value.nil?
            return false
          end

          # this attribute has to match or we failed
          unless @matcher_repository.find_matcher(attr).match(supplied_value, attr)
            return false
          end
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

