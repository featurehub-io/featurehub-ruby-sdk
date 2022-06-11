# frozen_string_literal: true

require "rack"
require 'sinatra'
require "featurehub-sdk"

def configure_featurehub
  config = FeatureHub::Sdk::FeatureHubConfig.new(ENV.fetch("FEATUREHUB_EDGE_URL", "https://zjbisc.demo.featurehub.io"),
                                                 [
                                                   ENV.fetch("FEATUREHUB_CLIENT_API_KEY",
                                                             "default/9b71f803-da79-4c04-8081-e5c0176dda87/CtVlmUHirgPd9Qz92Y0IQauUMUv3Wb*4dacoo47oYp6hSFFjVkG")
                                                 ])
  config.init
  config
end

# sample app
class App < Sinatra::Base
  # Middleware
  # use Rack::CanonicalHost, ENV['CANONICAL_HOST']
  configure do
    rack = File.new("logs/rack.log", "a+")
    use Rack::CommonLogger, rack

    set :fh_config, configure_featurehub
  end

  # Routes
  get("/") do
    if settings.fh_config.new_context.feature("FEATURE_TITLE_TO_UPPERCASE").enabled?
      "HELLO WORLD"
    else
      "Hello World"
    end
  end
end
