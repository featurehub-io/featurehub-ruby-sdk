# frozen_string_literal: true

# configure FeatureHub. Mostly taken from the rails portion of this doc:
# https://github.com/featurehub-io/featurehub-ruby-sdk/tree/main#2-create-featurehub-config
Rails.configuration.fh_config = FeatureHub::Sdk::FeatureHubConfig.new(
  ENV.fetch("FEATUREHUB_EDGE_URL"),
  [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")]
).init
