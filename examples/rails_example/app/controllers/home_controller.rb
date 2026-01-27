# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @flag_globally_enabled = Rails.configuration.fh_config.new_context.build.feature(:demo_feature).flag
    @flag_enabled_for_user_key = Rails.configuration.fh_config.new_context.user_key("some_key")
                                      .build.feature(:demo_feature).flag
    @flag_enabled_for_custom_splitting_rule = Rails.configuration.fh_config
                                                   .new_context.attribute_value("location_id", [5])
                                                   .build.feature(:demo_feature).flag
  end
end
