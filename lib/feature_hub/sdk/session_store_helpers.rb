# frozen_string_literal: true

require "digest"

module FeatureHub
  module Sdk
    # Shared pure helpers for MemcacheSessionStore and RedisSessionStore.
    # Both stores rely on SHA256-based change detection and a two-key layout:
    #   ${prefix}_${environment_id}      → JSON array of FeatureState objects
    #   ${prefix}_${environment_id}_sha  → SHA256 of "id:version|..." for change detection
    module SessionStoreHelpers
      private

      def calculate_sha(features)
        parts = features.map { |f| "#{f["id"]}:#{version_of(f)}" }.join("|")
        Digest::SHA256.hexdigest(parts)
      end

      def merge_features(base, updates)
        result = base.dup
        updates.each do |update|
          idx = result.find_index { |f| f["id"] == update["id"] }
          if idx
            result[idx] = update if version_of(update) > version_of(result[idx])
          else
            result << update
          end
        end
        result
      end

      def version_of(feature)
        (feature["version"] || 0).to_i
      end

      def features_key
        "#{@prefix}_#{@environment_id}"
      end

      def sha_key
        "#{@prefix}_#{@environment_id}_sha"
      end
    end
  end
end
