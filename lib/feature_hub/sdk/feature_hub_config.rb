# frozen_string_literal: true

module FeatureHub
  module Sdk
    # interface style definition for all edge services
    class EdgeService
      attr_reader :repository

      def initialize(repository, api_keys, edge_url, logger = nil)
        @repository = repository
        @api_keys = api_keys
        @edge_url = edge_url
        @logger = logger
      end

      # abstract
      def poll; end

      # abstract
      def context_change(new_header) end

      # abstract
      def close; end
    end

    # central dispatch class for FeatureHub SDK
    class FeatureHubConfig
      FALLBACK_ENVIRONMENT_ID = "569b0129-d53d-4516-a818-9154af601047"

      attr_reader :edge_url, :api_keys, :client_evaluated, :logger

      def initialize(edge_url = nil, api_keys = nil, repository = nil, edge_provider = nil, logger = nil) # rubocop:disable Metrics/ParameterLists
        @logger = logger
        @repository = repository || FeatureHub::Sdk::FeatureHubRepository.new(nil, @logger)

        resolved_url = resolve_edge_url(edge_url)
        resolved_keys = resolve_api_keys(api_keys)

        if resolved_url && resolved_keys && !resolved_keys.empty?
          detect_client_evaluated(resolved_keys)
          @edge_url = parse_edge_url(resolved_url)
          @api_keys = resolved_keys
          @edge_service_provider = edge_provider || method(:create_default_provider)
        else
          @edge_url = nil
          @api_keys = []
          @client_evaluated = false
          @edge_service_provider = edge_provider || method(:create_null_provider)
        end
      end

      def repository(repo = nil)
        @repository = repo || @repository
      end

      def feature(key, attrs = nil)
        @repository.feature(key, attrs)
      end

      def value(key, default_value = nil, attrs = nil)
        @repository.value(key, default_value, attrs)
      end

      def register_interceptor(interceptor)
        @repository.register_interceptor(interceptor)
      end

      def register_raw_update_listener(listener)
        @repository ||= FeatureHub::Sdk::FeatureHubRepository.new(nil, @logger)
        @repository.register_raw_update_listener(listener)
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

      def use_polling_edge_service(interval = ENV.fetch("FEATUREHUB_POLL_INTERVAL", "30").to_i)
        @interval = interval
        @edge_service_provider = method(:create_polling_edge_provider)
      end

      def new_context
        get_or_create_edge_service

        if @client_evaluated
          ClientEvalFeatureContext.new(@repository, @edge_service)
        else
          ServerEvalFeatureContext.new(@repository, @edge_service)
        end
      end

      def close
        unless @repository.nil?
          @repository.close
          @repository = nil
        end

        return if @edge_service.nil?

        @edge_service.close
        @edge_service = nil
      end

      def close_edge
        return if @edge_service.nil?

        @edge_service.close
        @edge_service = nil
      end

      def environment_id
        return FALLBACK_ENVIRONMENT_ID if @api_keys.empty?

        parts = @api_keys.first.split("/")
        parts.length == 3 ? parts[1] : parts[0]
      end

      private

      def create_edge_service
        @edge_service_provider.call(@repository, @api_keys, @edge_url, @logger)
      end

      def create_polling_edge_provider(repo, api_keys, edge_url, logger)
        FeatureHub::Sdk::PollingEdgeService.new(repo, api_keys, edge_url, @interval, logger)
      end

      def create_default_provider(repo, api_keys, edge_url, logger)
        FeatureHub::Sdk::StreamingEdgeService.new(repo, api_keys, edge_url, logger)
      end

      def resolve_edge_url(edge_url)
        url = edge_url.nil? || edge_url.strip.empty? ? ENV.fetch("FEATUREHUB_EDGE_URL", nil) : edge_url
        url&.strip&.empty? ? nil : url
      end

      def resolve_api_keys(api_keys)
        return api_keys if api_keys.is_a?(Array) && !api_keys.empty?

        [ENV.fetch("FEATUREHUB_CLIENT_API_KEY", nil), ENV.fetch("FEATUREHUB_SERVER_API_KEY", nil)].compact
      end

      def create_null_provider(repo, api_keys, edge_url, logger)
        EdgeService.new(repo, api_keys, edge_url, logger)
      end

      def detect_client_evaluated(api_keys)
        @client_evaluated = !api_keys.detect { |k| k.include?("*") }.nil?
        if api_keys.detect { |k| (@client_evaluated && !k.include?("*")) || (!@client_evaluated && k.include?("*")) }
          raise "api keys must all be of one type"
        end
      end

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
