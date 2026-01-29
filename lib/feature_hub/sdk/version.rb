# frozen_string_literal: true

module FeatureHub
  # already documented elsewhere
  module Sdk
    VERSION = "1.3.0"

    def default_logger
      log = ::Logger.new($stdout)
      log.level = ::Logger::WARN
      log.progname = "featurehub-sdk"
      log
    end

    module_function :default_logger
  end
end
