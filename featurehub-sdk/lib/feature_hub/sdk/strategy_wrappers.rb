# frozen_string_literal: true

require "sem_version"

module FeatureHub
  module Sdk
    # generic strategy matcher (and fallthrough)
    class StrategyMatcher
      def match(supplied_value, attr) # rubocop:disable Lint/UnusedMethodArgument
        false
      end
    end

    class BooleanMatcher < StrategyMatcher
      def match(supplied_value, attr)
        val = "true" == supplied_value.downcase

        if attr.conditional.equals?
          val == (attr.values[0].to_s.downcase == "true")
        elsif attr.conditional.not_equals?
          val != (attr.values[0].to_s.downcase == "true")
        else
          false
        end
      end
    end

    class StringMatcher < StrategyMatcher
      def match(supplied_value, attr)
        vals = attr.str_values

        cond = attr.conditional
        if cond.equals?
          !vals.detect { |v| supplied_value == v }.nil?
        elsif cond.not_equals?
          !vals.detect { |v| supplied_value != v }.nil?
        elsif cond.ends_with?
          !vals.detect { |v| supplied_value.end_with?(v) }.nil?
        elsif cond.starts_with?
          !vals.detect { |v| supplied_value.start_with?(v) }.nil?
        elsif cond.greater?
          !vals.detect { |v| supplied_value > v }.nil?
        elsif cond.greater_equals?
          !vals.detect { |v| supplied_value >= v }.nil?
        elsif cond.less?
          !vals.detect { |v| supplied_value < v }.nil?
        elsif cond.less_equals?
          !vals.detect { |v| supplied_value <= v }.nil?
        elsif cond.includes?
          !vals.detect { |v| supplied_value.include?(v) }.nil?
        elsif cond.excludes?
          vals.detect { |v| supplied_value.include?(v) }.nil?
        elsif cond.regex?
          vals.detect { |v| supplied_value.match(Regexp.new(v)) }.nil?
        else
          false
        end
      end
    end

    class NumberMatcher < StrategyMatcher
      def match(supplied_value, attr)
        cond = attr.conditional

        if cond.ends_with?
          !attr.str_values.detect { |v| supplied_value.end_with?(v) }.nil?
        elsif cond.starts_with?
          !attr.str_values.detect { |v| supplied_value.start_with?(v) }.nil?
        elsif cond.regex?
          attr.str_values.detect { |v| supplied_value.match(Regexp.new(v)) }.nil?
        else
          parsed_val = supplied_value.to_f
          vals = attr.float_values

          if cond.equals?
            !vals.detect { |v| parsed_val == v }.nil?
          elsif cond.equals?
            !vals.detect { |v| parsed_val != v }.nil?
          elsif cond.greater?
            !vals.detect { |v| parsed_val > v }.nil?
          elsif cond.greater_equals?
            !vals.detect { |v| parsed_val >= v }.nil?
          elsif cond.less?
            !vals.detect { |v| parsed_val < v }.nil?
          elsif cond.less_equals?
            !vals.detect { |v| parsed_val <= v }.nil?
          elsif cond.includes?
            !vals.detect { |v| parsed_val.include?(v) }.nil?
          elsif cond.excludes?
            vals.detect { |v| parsed_val.include?(v) }.nil?
          else
            false
          end
        end
      end
    end
    # NumberMatcher

    class SemanticVersionMatcher < StrategyMatcher
      def match(supplied_value, attr)
        cond = attr.conditional

        val = SemVersion.new(supplied_value)
        vals = attr.str_values

        if cond.includes? || cond.equals?
          !vals.detect { |v| val.satisfies?(v) }.nil?
        elsif cond.excludes? || cond.not_equals?
          vals.detect { |v| val.satisfies?(v) }.nil?
        else
          comparison_vals = vals.filter { |x| SemVersion.valid?(x) }
          if cond.greater?
            !comparison_vals.detect { |v| supplied_value > v  }.nil?
          elsif cond.greater_equals?
            !comparison_vals.detect { |v| supplied_value >= v  }.nil?
          elsif cond.less?
            !comparison_vals.detect { |v| supplied_value < v  }.nil?
          elsif cond.less_equals?
            !comparison_vals.detect { |v| supplied_value <= v  }.nil?
          else
            false
          end
        end
      end
    end  # SemanticVersionMatcher

    # matches based on ip addresses and CIDRs
    class IpNetworkMatcher < StrategyMatcher
      def match(supplied_value, attr)
        cond = attr.conditional

        val = IPAddr.new(supplied_value)

        if cond.includes? || cond.equals?
          !vals.detect { |v| IPAddr.new(v).include?(val) }.nil?
        elsif cond.excludes? || cond.not_equals?
          vals.detect { |v| IPAddr.new(v).include?(val) }.nil?
        else
          false
        end
      end
    end

    # interface for the matcher repository finder
    class MatcherRepository
      def find_matcher(attr); end
    end

    # figures out what attribute type this is and passes back the right matcher
    class MatcherRegistry < MatcherRepository
      def find_matcher(attr)
        case attr.field_type
        when "STRING", "DATE", "DATETIME"
          FeatureHub::Sdk::StringMatcher.new
        when "SEMANTIC_VERSION"
          FeatureHub::Sdk::SemanticVersionMatcher.new
        when "NUMBER"
          FeatureHub::Sdk::NumberMatcher.new
        when "IP_ADDRESS"
          FeatureHub::Sdk::INetworkMatcher.new
        else
          FeatureHub::Sdk::StrategyMatcher.new
        end
      end
    end
  end
end
