# frozen_string_literal: true

require "ld-eventsource"
require "json"

module FeatureHub
  module Sdk
    # provides a streaming service
    class StreamingEdgeService < FeatureHub::Sdk::EdgeService
      attr_reader :repository, :sse_client, :url, :closed

      def initialize(repository, api_keys, edge_url, logger = nil)
        super(repository, api_keys, edge_url)

        @url = "#{edge_url}features/#{api_keys[0]}"
        @repository = repository
        @sse_client = nil
        @closed = true
        @logger = logger || FeatureHub::Sdk.default_logger
      end

      def poll
        start_streaming unless @sse_client
      end

      def active
        !@closed && !@sse_client.nil?
      end

      def close
        @closed = true
        return if @sse_client.nil?

        @sse_client.close
        @sse_client = nil
      end

      private

      def start_streaming
        @closed = false
        @logger.info("streaming from #{@url}")
        @sse_client = SSE::Client.new(@url) do |client|
          client.on_event do |event|
            @repository.notify(event.type, JSON.parse(event.data))
          end
          client.on_error do |error|
            if error.is_a?(SSE::Errors::HTTPStatusError) && (error.status == 404)
              @repository.notify("failure", nil)
              close
            end
          end
        end
      end
    end
  end
end
