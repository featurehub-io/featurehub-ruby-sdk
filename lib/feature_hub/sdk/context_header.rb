# frozen_string_literal: true

require "digest/sha2"
require "time"

module FeatureHub
  module Sdk
    # The x-featurehub header and contextSha exactly as featurehub-protocol.yaml encoding.evaluation_context
    # specifies them, so every FeatureHub SDK sends the same values for the same context.
    module ContextHeader
      # bytes left as they are by JavaScript's encodeURIComponent: A-Z a-z 0-9 - _ . ! ~ * ' ( )
      UNRESERVED = (("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[- _ . ! ~ * ' ( )])
                   .map(&:ord).freeze

      module_function

      # Each attribute with at least one non-nil value becomes encode_uri_component(key) + "=" +
      # encode_uri_component(values joined by ","); the encoded strings are sorted by ordinal comparison
      # and joined with ",". Returns an empty string when no attribute has a value.
      def x_featurehub_header(attributes)
        return "" if attributes.nil?

        attributes.filter_map do |key, values|
          wire = Array(values).compact.map { |v| wire_value(v) }
          next if wire.empty?

          "#{encode_uri_component(key.to_s)}=#{encode_uri_component(wire.join(","))}"
        end.sort.join(",")
      end

      # The SHA-256 of the header as 64 lowercase hex characters, or "0" when there is no header.
      def context_sha(header)
        header.nil? || header.empty? ? "0" : Digest::SHA256.hexdigest(header)
      end

      # Encodes as JavaScript's encodeURIComponent does: UTF-8, then every byte except
      # A-Z a-z 0-9 - _ . ! ~ * ' ( ) as %XX with uppercase hex. URI.encode_www_form_component is form
      # encoding (a space as "+") and encodes ~ ! ' ( ), so it is not used.
      def encode_uri_component(value)
        value.to_s.encode(Encoding::UTF_8).bytes.map do |b|
          UNRESERVED.include?(b) ? b.chr : format("%%%02X", b)
        end.join
      end

      # How a value becomes a string (featurehub-protocol.yaml encoding.evaluation_context.wire_value),
      # following JavaScript's String(): whole floats have no fraction (3.0 -> "3"), and times are UTC ISO-8601.
      def wire_value(value)
        case value
        when Float
          if value.nan?
            "NaN"
          elsif value.infinite?
            value.positive? ? "Infinity" : "-Infinity"
          elsif value == value.truncate
            value.to_i.to_s
          else
            value.to_s
          end
        when Time
          value.utc.iso8601(3)
        when DateTime
          value.to_time.utc.iso8601(3)
        else
          value.to_s
        end
      end
    end
  end
end
