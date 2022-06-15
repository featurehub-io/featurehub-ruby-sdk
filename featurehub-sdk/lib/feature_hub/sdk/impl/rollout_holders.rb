# frozen_string_literal: true

# these are bulk copied in from OpenAPI and left in original case
module FeatureHub
  module Sdk
    module Impl
      # represents a condition for this attribute
      class RolloutStrategyAttributeCondition
        def initialize(attr)
          @attr = attr
        end

        def equals?
          @attr == "EQUALS"
        end

        def ends_with?
          @attr == "ENDS_WITH"
        end

        def starts_with?
          @attr == "STARTS_WITH"
        end

        def greater?
          @attr == "GREATER"
        end

        def greater_equals?
          @attr == "GREATER_EQUALS"
        end

        def less?
          @attr == "LESS"
        end

        def less_equals?
          @attr == "LESS_EQUALS"
        end

        def not_equals?
          @attr == "NOT_EQUALS"
        end

        def includes?
          @attr == "INCLUDES"
        end

        def excludes?
          @attr == "EXCLUDES"
        end

        def regex?
          @attr == "REGEX"
        end

        def to_s
          @attr
        end
      end

      # represents an individual attribute comparison
      class RolloutStrategyAttribute
        attr_reader :id, :conditional, :field_name, :values, :field_type

        def initialize(attr)
          @attr = attr
          @id = @attr["id"]
          @conditional = RolloutStrategyAttributeCondition.new(@attr["conditional"])
          @field_name = @attr["fieldName"]
          @values = @attr["values"]
          @field_type = @attr["type"]
        end

        def float_values
          @values.filter { |x| !x.nil? }.map(&:to_f)
        end

        def str_values
          @values.filter { |x| !x.nil? }.map(&:to_s)
        end

        def to_s
          "id: #{@id}, conditional: #{@conditional}, field_name: #{@field_name}, " \
            "values: #{@values}, field_type: #{field_type}"
        end
      end

      # represents a raw rollout strategy inside a feature
      class RolloutStrategy
        attr_reader :attributes, :id, :name, :percentage, :percentage_attributes, :value

        def initialize(strategy)
          @strategy = strategy
          @attributes = (strategy["attributes"] || []).map { |attr| RolloutStrategyAttribute.new(attr) }
          @id = strategy["id"]
          @name = strategy["name"]
          @percentage = (strategy["percentage"] || "0").to_i
          @percentage_attributes = (strategy["percentageAttributes"] || [])
          @value = strategy["value"]
        end

        def percentage_attributes?
          !@percentage_attributes.empty?
        end

        def attributes?
          !@attributes.empty?
        end

        def to_s
          "id: #{@id}, name: #{@name}, percentage: #{@percentage}, percentage_attrs: #{@percentage_attributes}, " \
            "value: #{@value}, attributes: [#{@attributes.map(&:to_s).join(",")}]"
        end
      end
    end
  end
end
