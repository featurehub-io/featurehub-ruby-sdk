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

      def initialize(repository, api_keys, edge_url, interval)
        super(repository, api_keys, edge_url)

        @repository = repository
        @api_keys = api_keys
        @edge_url = edge_url
        @interval = interval

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

        puts("creating task for #{@interval}")
        @task = Concurrent::TimerTask.new(execution_interval: @interval) do
          puts("interval firing")
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
        resp = @conn.get(url, request: { timeout: @timeout }, headers: headers)
        case resp.status
        when 200
          @etag = resp.headers["etag"]
          puts("etag is #{@etag}")
          process_results(JSON.parse(resp.body))
        when 404 # no such key
          @repository.notify("failed", nil)
          @cancel = true
          puts("key does not exist")
        when 503 # dacha busy
          puts("dacha busy, retrying on next")
        else
          puts("unknown failure #{resp.status}")
        end
      end
      # rubocop:enable Naming/AccessorMethodName

      def process_results(data)
        puts("found data ", data)

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
        @url = "/features?#{api_key_cat}"
        @timeout = ENV.fetch("FEATUREHUB_POLL_HTTP_TIMEOUT", "12").to_i
        @conn = Faraday.new(url: @edge_url) do |f|
          f.adapter :net_http
        end
      end
    end
  end
end
