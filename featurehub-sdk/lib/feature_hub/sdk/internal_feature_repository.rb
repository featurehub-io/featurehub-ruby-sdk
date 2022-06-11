# frozen_string_literal: true

module FeatureHub
  module Sdk
    # surface features of a repository that must be implemented for any repository wrapper
    class InternalFeatureRepository
      def feature(_key)
        nil
      end

      def find_interceptor(_feature_value)
        nil
      end

      def ready?
        false
      end

      def not_ready!; end

      def apply(_strategies, _key, _feature_id, _context)
        Applied.new(false, nil)
      end

      def notify(status, data); end
    end
  end
end
