# frozen_string_literal: true

require "ld-eventsource"
require "json"

module FeatureHub
  module Sdk
    # provides a streaming service
    class StreamingEdgeService < FeatureHub::Sdk::EdgeService
      attr_reader :repository, :sse_client, :url, :stopped

      def initialize(repository, api_keys, edge_url, logger = nil)
        super(repository, api_keys, edge_url)

        @url = "#{edge_url}features/#{api_keys[0]}"
        @repository = repository
        @sse_client = nil
        @context = nil
        @logger = logger || FeatureHub::Sdk.default_logger
      end

      def closed
        @sse_client.nil?
      end

      def poll
        start_streaming unless @sse_client || @stopped
      end

      def active
        !@sse_client.nil?
      end

      def close
        close_connection
      end

      private

      def close_connection
        return if @sse_client.nil?

        @sse_client.close
        @sse_client = nil
      end

      def stop
        @stopped = true
        close_connection
      end

      def context_change(new_header)
        return if new_header == @context

        @context = new_header
        close
        poll
      end

      def start_streaming
        @logger.info("streaming from #{@url}")
        # we can get an error before returning the new() function and get a race condition on the close
        must_close = false
        @sse_client = SSE::Client.new(@url) do |client|
          client.on_event do |event|
            json_data = JSON.parse(event.data)

            if event.type == "config"
              process_config(json_data)
            else
              @repository.notify(event.type, json_data)
            end
          end
          client.on_error do |error|
            if error.is_a?(SSE::Errors::HTTPStatusError) && (error.status == 404)
              @repository.notify("failure", nil)
              close
              must_close = true
            end
          end
        end

        return unless must_close

        close  # try again
      end

      def process_config(json_data)
        stop if json_data["edge.stale"]
      end
    end
  end
end
