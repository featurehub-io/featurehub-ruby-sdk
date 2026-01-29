# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::EnvironmentInterceptor do
  it "should pick up overrides from the environment" do
    expect(ENV).to receive(:fetch).with("FEATUREHUB_OVERRIDE_FEATURES", "false").and_return("true")
    expect(ENV).to receive(:fetch).with("FEATUREHUB_blah", nil).and_return("ruby")

    val = FeatureHub::Sdk::EnvironmentInterceptor.new.intercepted_value(:blah)
    expect(val).to_not eq(nil)
    expect(val.cast("STRING")).to eq("ruby")
  end
end
