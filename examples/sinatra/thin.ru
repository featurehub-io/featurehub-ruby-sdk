# frozen_string_literal: true

require "thin"
require_relative "app/application"

require "bundler"
Bundler.setup(:default)

run App
