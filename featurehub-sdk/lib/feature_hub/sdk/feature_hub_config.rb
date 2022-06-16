# frozen_string_literal: true

module FeatureHub
  module Sdk
    # interface style definition for all edge services
    class EdgeService
      # abstract
      def initialize(repository, api_keys, edge_url, logger = nil) end

      # abstract
      def poll; end

      # abstract
      def context_change(new_header) end

      # abstract
      def close; end
    end

    # central dispatch class for FeatureHub SDK
    class FeatureHubConfig
      attr_reader :edge_url, :api_keys, :client_evaluated, :logger

      def initialize(edge_url, api_keys, repository = nil, edge_provider = nil, logger = nil)
        raise "edge_url is not set to a valid string" if edge_url.nil? || edge_url.strip.empty?

        raise "api_keys must be an array of API keys" if api_keys.nil? || !api_keys.is_a?(Array) || api_keys.empty?

        detect_client_evaluated(api_keys)

        @edge_url = parse_edge_url(edge_url)
        @api_keys = api_keys
        @repository = repository || FeatureHub::Sdk::FeatureHubRepository.new
        @edge_service_provider = edge_provider || method(:create_default_provider)
        @logger = logger || FeatureHub::Sdk.default_logger
      end

      def repository(repo = nil)
        @repository = repo || @repository
      end

      def init
        get_or_create_edge_service.poll
        self
      end

      def force_new_edge_service
        if @edge_service
          @edge_service&.close
          @edge_service = nil
        end

        get_or_create_edge_service
      end

      # rubocop:disable Naming/AccessorMethodName
      def get_or_create_edge_service
        @edge_service = create_edge_service if @edge_service.nil?

        @edge_service
      end
      # rubocop:enable Naming/AccessorMethodName

      def edge_service_provider(edge_provider = nil)
        return @edge_service_provider if edge_provider.nil?

        @edge_service_provider = edge_provider

        if @edge_service
          @edge_service&.close
          @edge_service = nil
        end

        edge_provider
      end

      def use_polling_edge_service(interval = ENV.fetch("FEATUREHUB_POLL_INTERVAL", "30").to_i); end

      def new_context
        get_or_create_edge_service

        if @client_evaluated
          ClientEvalFeatureContext.new(@repository, @edge_service)
        else
          ServerEvalFeatureContext.new(@repository, @edge_service)
        end
      end

      def close
        return if @edge_service.nil?

        @edge_service.close
        @edge_service = nil
      end

      private

      def create_edge_service
        @edge_service_provider.call(@repository, @api_keys, @edge_url, @logger)
      end

      def create_default_provider(repo, api_keys, edge_url, logger)
        # FeatureHub::Sdk::PollingEdgeService.new(repo, api_keys, edge_url, 10, logger)
        FeatureHub::Sdk::StreamingEdgeService.new(repo, api_keys, edge_url, logger)
      end

      # rubocop:disable Style/GuardClause
      def detect_client_evaluated(api_keys)
        @client_evaluated = !api_keys.detect { |k| k.include?("*") }.nil?
        if api_keys.detect { |k| (@client_evaluated && !k.include?("*")) || (!@client_evaluated && k.include?("*")) }
          raise "api keys must all be of one type"
        end
      end
      # rubocop:enable Style/GuardClause

      def parse_edge_url(edge_url)
        if edge_url[-1] == "/"
          edge_url
        else
          "#{edge_url}/"
        end
      end
    end
  end
end
