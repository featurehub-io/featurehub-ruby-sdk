# frozen_string_literal: true

require "faraday"
require "faraday/net_http"
require "json"
require "concurrent-ruby"
require "digest/sha2"

module FeatureHub
  module Sdk
    # uses a periodic polling mechanism to get updates
    class PollingEdgeService < EdgeService
      attr_reader :repository, :api_keys, :edge_url, :interval, :stopped, :etag, :cancel, :sha_context

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
        @stopped = false
        @sha_context = nil

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
        @sha_context = Digest::SHA256.hexdigest(@context)

        if active
          get_updates
        else
          poll
        end
      end

      def close
        cancel_task
      end

      def active
        !@task.nil?
      end

      private

      def poll_with_interval
        return if @cancel || !@task.nil? || @stopped

        @logger.info("starting polling for #{determine_request_url}")
        @task = Concurrent::TimerTask.new(execution_interval: @interval, run_now: false) do
          get_updates
        end

        get_updates

        @task&.execute # could have been shutdown
      end

      def cancel_task
        @cancel = true
        shutdown_task
      end

      def stopped_task
        @stopped = true
        shutdown_task
      end

      def shutdown_task
        return if @task.nil?

        @task.shutdown
        @task = nil
      end

      # rubocop:disable Naming/AccessorMethodName
      def get_updates
        url = determine_request_url
        headers = {
          accept: "application/json",
          "X-SDK": "Ruby",
          "X-SDK-Version": FeatureHub::Sdk::VERSION
        }

        headers["x-featurehub"] = @context unless @context.nil?
        headers["if-none-match"] = @etag unless @etag.nil?

        @logger.debug("polling for #{url}")
        resp = @conn.get url, {}, headers
        case resp.status
        when 200
          success(resp)
        when 236
          stopped_task
          success(resp)
        when 404 # no such key
          @repository.notify("failed", nil)
          cancel_task
          @logger.error("featurehub: key does not exist, stopping polling")
        when 503 # dacha busy
          @logger.debug("featurehub: dacha is busy, trying again")
        else
          @logger.debug("featurehub: unknown error #{resp.status}")
        end
      end

      # rubocop:enable Naming/AccessorMethodName

      def success(resp)
        @etag = resp.headers["etag"]

        check_interval_change(resp.headers["cache-control"]) if resp.headers["cache-control"]

        process_results(JSON.parse(resp.body))
      end

      def process_results(data)
        data.each do |environment|
          @repository.notify("features", environment["features"]) if environment
        end
      end

      def check_interval_change(cache_control_header)
        found = cache_control_header.scan(/max-age=(\d+)/)

        return if @task.nil? || found.empty? || found[0].empty?

        new_interval = found[0][0].to_i

        return unless new_interval.positive? && new_interval != @interval

        @interval = new_interval
        @task.execution_interval = @interval
      end

      def determine_request_url
        if @context.nil?
          "#{@url}&contextSha=0"
        else
          "#{@url}&contextSha=#{@sha_context}"
        end
      end

      def generate_url
        api_key_cat = (@api_keys.map { |key| "apiKey=#{key}" } * "&")
        @url = "features?#{api_key_cat}"
        @timeout = ENV.fetch("FEATUREHUB_POLL_HTTP_TIMEOUT", "12").to_i
        @conn = Faraday.new(url: @edge_url) do |f|
          f.adapter :net_http
          f.options.timeout = @timeout
        end
      end
    end
  end
end
