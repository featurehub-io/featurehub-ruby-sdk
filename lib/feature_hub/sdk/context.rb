# frozen_string_literal: true

require "json"

module FeatureHub
  module Sdk
    module ContextKeys
      USERKEY = :userkey
      SESSION = :session
      COUNTRY = :country
      PLATFORM = :platform
      DEVICE = :device
      VERSION = :version
    end

    # the context holding user data
    class ClientContext
      attr_reader :repo

      WELL_KNOWN_KEY_METHODS = {
        ContextKeys::USERKEY => :user_key,
        ContextKeys::SESSION => :session_key,
        ContextKeys::COUNTRY => :country,
        ContextKeys::PLATFORM => :platform,
        ContextKeys::DEVICE => :device,
        ContextKeys::VERSION => :version
      }.freeze

      def initialize(repo, attrs = nil)
        @repo = repo
        @attributes = {}
        assign(attrs) if attrs
      end

      def user_key(value)
        @attributes[ContextKeys::USERKEY] = [value]
        self
      end

      def session_key(value)
        @attributes[ContextKeys::SESSION] = [value]
        self
      end

      def country(value)
        @attributes[ContextKeys::COUNTRY] = [value]
        self
      end

      def device(value)
        @attributes[ContextKeys::DEVICE] = [value]
        self
      end

      def platform(value)
        @attributes[ContextKeys::PLATFORM] = [value]
        self
      end

      def version(value)
        @attributes[ContextKeys::VERSION] = [value]
        self
      end

      # this takes an array parameter
      def attribute_value(key, values)
        return self if key.nil? || key.to_s.empty?

        if values.nil? || values.empty?
          @attributes.delete(key.to_sym)
        else
          @attributes[key.to_sym] = if values.is_a?(Array)
                                      values
                                    else
                                      [values]
                                    end
        end

        self
      end

      def assign(attrs)
        attrs.each do |key, value|
          sym_key = key.to_sym
          method_name = WELL_KNOWN_KEY_METHODS[sym_key]
          if method_name
            send(method_name, value)
          else
            attribute_value(sym_key, value)
          end
        end
        self
      end

      def clear
        @attributes = {}
        self
      end

      def get_attr(key, default_val = nil)
        (@attributes[key.to_sym] || [default_val]).compact
      end

      def default_percentage_key
        key = @attributes[ContextKeys::SESSION] || @attributes[ContextKeys::USERKEY]
        if key.nil? || key.empty?
          nil
        else
          key[0]
        end
      end

      def enabled?(key)
        feature(key).enabled?
      end

      def feature(key)
        @repo.feature(key).with_context(self)
      end

      def set?(key)
        feature(key).set?
      end

      def number(key)
        feature(key).number
      end

      def string(key)
        feature(key).string
      end

      def json(key)
        data = feature(key).raw_json
        return JSON.parse(data) if data

        nil
      end

      def raw_json(key)
        feature(key).raw_json
      end

      def flag(key)
        feature(key).flag
      end

      def boolean(key)
        feature(key).boolean
      end

      def exists?(key)
        feature(key).exists?
      end

      def build
        self
      end

      def build_sync
        self
      end
    end

    # represents the strategies being evaluated locally
    class ClientEvalFeatureContext < ClientContext
      def initialize(repo, edge)
        super(repo)

        @edge = edge
      end

      def build
        @edge&.poll
        self
      end

      def build_sync
        self
      end
    end

    # context used when evaluating server side
    class ServerEvalFeatureContext < ClientContext
      def initialize(repo, edge)
        super(repo)

        @edge = edge
        @old_header = nil
      end

      def build
        return self unless @edge

        new_header = @attributes.map { |k, v| "#{k}=#{URI.encode_www_form_component(v[0].to_s)}" } * "&"

        if @old_header.nil? && new_header.empty?
          @edge.poll
        elsif new_header != @old_header
          @old_header = new_header
          @repo.not_ready!

          @edge.context_change(new_header)
        end

        self
      end

      def build_sync
        build
      end
    end
  end
end
