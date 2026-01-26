# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk do
  it "has a version number" do
    expect(FeatureHub::Sdk::VERSION).not_to be nil
  end
end
