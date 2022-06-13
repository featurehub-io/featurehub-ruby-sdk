# frozen_string_literal: true

require "sem_version"

module FeatureHub
  module Sdk
    module Impl
      # generic strategy matcher (and fallthrough)
      class StrategyMatcher
        def match(_supplied_value, _attr)
          false
        end
      end

      # comparison for true/false
      class BooleanMatcher < StrategyMatcher
        def match(supplied_value, attr)
          val = supplied_value.downcase == "true"

          if attr.conditional.equals?
            val == (attr.values[0].to_s.downcase == "true")
          elsif attr.conditional.not_equals?
            val != (attr.values[0].to_s.downcase == "true")
          else
            false
          end
        end
      end

      # matches for strings, dates and date-times
      class StringMatcher < StrategyMatcher
        def match(supplied_value, attr)
          vals = attr.str_values

          cond = attr.conditional
          if cond.equals?
            vals.any? { |v| supplied_value == v }
          elsif cond.not_equals?
            vals.none? { |v| supplied_value == v }
          elsif cond.ends_with?
            vals.any? { |v| supplied_value.end_with?(v) }
          elsif cond.starts_with?
            vals.any? { |v| supplied_value.start_with?(v) }
          elsif cond.greater?
            vals.any? { |v| supplied_value > v }
          elsif cond.greater_equals?
            vals.any? { |v| supplied_value >= v }
          elsif cond.less?
            vals.any? { |v| supplied_value < v }
          elsif cond.less_equals?
            vals.any? { |v| supplied_value <= v }
          elsif cond.includes?
            vals.any? { |v| supplied_value.include?(v) }
          elsif cond.excludes?
            vals.none? { |v| supplied_value.include?(v) }
          elsif cond.regex?
            vals.any? { |v| !Regexp.new(v).match(supplied_value).nil? }
          else
            false
          end
        end
      end

      # matches floating point numbers excep for end/start/regexp
      class NumberMatcher < StrategyMatcher
        def match(supplied_value, attr)
          cond = attr.conditional

          if cond.ends_with?
            attr.str_values.any? { |v| supplied_value.end_with?(v) }
          elsif cond.starts_with?
            attr.str_values.any? { |v| supplied_value.start_with?(v) }
          elsif cond.excludes?
            attr.str_values.none? { |v| supplied_value.include?(v) }
          elsif cond.includes?
            attr.str_values.any? { |v| supplied_value.include?(v) }
          elsif cond.regex?
            attr.str_values.any? { |v| !Regexp.new(v).match(supplied_value).nil? }
          else
            parsed_val = supplied_value.to_f
            vals = attr.float_values

            if cond.equals?
              vals.any? { |v| parsed_val == v }
            elsif cond.not_equals?
              vals.none? { |v| parsed_val == v }
            elsif cond.greater?
              vals.any? { |v| parsed_val > v }
            elsif cond.greater_equals?
              vals.any? { |v| parsed_val >= v }
            elsif cond.less?
              vals.any? { |v| parsed_val < v }
            elsif cond.less_equals?
              vals.any? { |v| parsed_val <= v }
            elsif cond.includes?
              vals.any? { |v| parsed_val.include?(v) }
            elsif cond.excludes?
              vals.none? { |v| parsed_val.include?(v) }
            else
              false
            end
          end
        end
      end

      # NumberMatcher

      # matches using semantic versions
      class SemanticVersionMatcher < StrategyMatcher
        def match(supplied_value, attr)
          cond = attr.conditional

          val = SemVersion.new(supplied_value)
          vals = attr.str_values

          if cond.includes? || cond.equals?
            vals.any? { |v| val.satisfies?(v) }
          elsif cond.excludes? || cond.not_equals?
            vals.none? { |v| val.satisfies?(v) }
          else
            comparison_vals = vals.filter { |x| SemVersion.valid?(x) }
            if cond.greater?
              comparison_vals.any? { |v| supplied_value > v }
            elsif cond.greater_equals?
              comparison_vals.any? { |v| supplied_value >= v }
            elsif cond.less?
              comparison_vals.any? { |v| supplied_value < v }
            elsif cond.less_equals?
              comparison_vals.any? { |v| supplied_value <= v }
            else
              false
            end
          end
        end
      end

      # matches based on ip addresses and CIDRs
      class IpNetworkMatcher < StrategyMatcher
        def match(supplied_value, attr)
          cond = attr.conditional

          val = IPAddr.new(supplied_value)
          vals = attr.str_values

          if cond.includes? || cond.equals?
            vals.any? { |v| IPAddr.new(v).include?(val) }
          elsif cond.excludes? || cond.not_equals?
            vals.none? { |v| IPAddr.new(v).include?(val) }
          else
            false
          end
        end
      end

      # interface for the matcher repository finder
      class MatcherRepository
        def find_matcher(attr)
          ;
        end
      end

      # figures out what attribute type this is and passes back the right matcher
      class MatcherRegistry < MatcherRepository
        def find_matcher(attr)
          case attr.field_type
          when "BOOLEAN"
            BooleanMatcher.new
          when "STRING", "DATE", "DATE_TIME"
            StringMatcher.new
          when "SEMANTIC_VERSION"
            SemanticVersionMatcher.new
          when "NUMBER"
            NumberMatcher.new
          when "IP_ADDRESS"
            IpNetworkMatcher.new
          else
            StrategyMatcher.new
          end
        end
      end
    end
  end
end
