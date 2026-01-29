# frozen_string_literal: true

require_relative "app/application"

require "bundler"
Bundler.setup(:default)

if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      puts("process forking, create a new edge instance #{App.settings}")
      App.settings.fh_config.force_new_edge_service
    end
  end
end

run App
