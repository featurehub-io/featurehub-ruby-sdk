# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::EnvironmentInterceptor do
  it "should pick up overrides from the environment" do
    expect(ENV).to receive(:fetch).with("FEATUREHUB_OVERRIDE_FEATURES", "false").and_return("true")
    expect(ENV).to receive(:fetch).with("FEATUREHUB_blah", nil).and_return("ruby")

    matched, val = FeatureHub::Sdk::EnvironmentInterceptor.new.intercepted_value(:blah, nil, nil)
    expect(matched).to eq(true)
    expect(val).to eq("ruby")
  end
end
