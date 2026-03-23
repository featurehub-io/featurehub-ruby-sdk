# frozen_string_literal: true

module FeatureHub
  module Sdk
    # Base class for listening to raw feature update events from edge services.
    # Subclass and override the methods you care about.
    class RawUpdateFeatureListener
      def delete_feature(_feature, _source); end

      def process_updates(_features, _source); end

      def process_update(_feature, _source); end

      def close; end

      def config_changed; end
    end
  end
end
