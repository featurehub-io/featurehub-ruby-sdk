# frozen_string_literal: true

require "faraday"
require "faraday/net_http"
require "json"
require "concurrent-ruby"

module FeatureHub
  module Sdk
    # uses a periodic polling mechanism to get updates
    class PollingEdgeService < EdgeService
      attr_reader :repository, :api_keys, :edge_url, :interval

      def initialize(repository, api_keys, edge_url, interval, logger = nil)
        super(repository, api_keys, edge_url)

        @repository = repository
        @api_keys = api_keys
        @edge_url = edge_url
        @interval = interval

        @logger = logger || FeatureHub::Sdk.default_logger

        @task = nil
        @cancel = false
        @context = nil
        @etag = nil

        generate_url
      end

      # abstract
      def poll
        @cancel = false
        poll_with_interval
      end

      def update_interval(interval)
        @interval = interval
        if @task.nil?
          poll
        else
          @task.execution_interval = interval
        end
      end

      def context_change(new_header)
        return if new_header == @context

        @context = new_header

        get_updates
      end

      def close
        cancel_task
      end

      private

      def poll_with_interval
        return if @cancel || !@task.nil?

        get_updates

        @logger.info("starting polling for #{determine_request_url}")
        @task = Concurrent::TimerTask.new(execution_interval: @interval) do
          get_updates
        end
        @task.execute
      end

      def cancel_task
        return if @task.nil?

        @task.shutdown
        @task = nil
        @cancel = true
      end

      # rubocop:disable Naming/AccessorMethodName
      def get_updates
        url = determine_request_url
        headers = {
          accept: "application/json",
          "X-SDK": "Ruby",
          "X-SDK-Version": FeatureHub::Sdk::VERSION
        }
        headers["if-none-match"] = @etag unless @etag.nil?
        @logger.debug("polling for #{url}")
        resp = @conn.get(url, request: { timeout: @timeout }, headers: headers)
        case resp.status
        when 200
          @etag = resp.headers["etag"]
          process_results(JSON.parse(resp.body))
        when 404 # no such key
          @repository.notify("failed", nil)
          @cancel = true
          @logger.error("featurehub: key does not exist, stopping polling")
        when 503 # dacha busy
          @logger.debug("featurehub: dacha is busy, trying tgaina")
        else
          @logger.debug("featurehub: unknown error #{resp.status}")
        end
      end
      # rubocop:enable Naming/AccessorMethodName

      def process_results(data)
        data.each do |environment|
          @repository.notify("features", environment["features"]) if environment
        end
      end

      def determine_request_url
        if @context.nil?
          @url
        else
          "#{@url}&#{@context}"
        end
      end

      def generate_url
        api_key_cat = (@api_keys.map { |key| "apiKey=#{key}" } * "&")
        @url = "features?#{api_key_cat}"
        @timeout = ENV.fetch("FEATUREHUB_POLL_HTTP_TIMEOUT", "12").to_i
        @conn = Faraday.new(url: @edge_url) do |f|
          f.adapter :net_http
        end
      end
    end
  end
end
