# frozen_string_literal: true

class ContextKeys
  include FeatureHub::Sdk::ContextKeys
end

require "json"

RSpec.describe FeatureHub::Sdk::ClientContext do
  before do
    @repo = instance_double(FeatureHub::Sdk::InternalFeatureRepository)
    @ctx = FeatureHub::Sdk::ClientContext.new(@repo)
  end

  it "should store and retrieve context" do
    expect(@ctx.user_key("fred").get_attr(ContextKeys::USER_KEY)).to eq("fred")
    country = FeatureHub::Sdk::StrategyAttributeCountryName::Afghanistan
    expect(@ctx.country(country).get_attr(ContextKeys::COUNTRY)).to eq(country)
    device = FeatureHub::Sdk::StrategyAttributeDeviceName::Browser
    expect(@ctx.device(device).get_attr(ContextKeys::DEVICE)).to eq(device)

    version = "1.567"
    expect(@ctx.version(version).get_attr(ContextKeys::VERSION)).to eq(version)

    expect(@ctx.attribute_value("flavour", "cumberlands").get_attr("flavour")).to eq("cumberlands")
    expect(@ctx.attribute_value("texture", %w[crisp hearty]).get_attr("texture")).to eq("crisp")

    platform = FeatureHub::Sdk::StrategyAttributePlatformName::Ios
    @ctx.platform(platform)
    expect(@ctx.get_attr(ContextKeys::PLATFORM)).to eq(platform)

    @ctx.clear
    expect(@ctx.get_attr(ContextKeys::PLATFORM)).to eq(nil)
  end

  it "should be able to use user or session value for default percentage" do
    @ctx.user_key("user")
    expect(@ctx.default_percentage_key).to eq("user")
    @ctx.session_key("session") # session overrides user
    expect(@ctx.default_percentage_key).to eq("session")
  end

  it "should support passthrough" do
    feature = instance_double(FeatureHub::Sdk::FeatureState)
    expect(@repo).to receive(:feature).with("str_feature").and_return(feature)
    expect(@repo.feature("str_feature")).to eq(feature)
  end

  describe "features support passthrough" do
    before do
      @feature = instance_double(FeatureHub::Sdk::FeatureState)
      expect(@repo).to receive(:feature).with("feature").and_return(@feature)
    end

    it "string" do
      expect(@feature).to receive(:string).and_return("str")
      expect(@ctx.string("feature")).to eq("str")
    end

    it "number" do
      expect(@feature).to receive(:number).and_return("number")
      expect(@ctx.number("feature")).to eq("number")
    end

    it "boolean" do
      expect(@feature).to receive(:boolean).and_return(true)
      expect(@ctx.boolean("feature")).to eq(true)
    end

    it "flag" do
      expect(@feature).to receive(:flag).and_return(true)
      expect(@ctx.flag("feature")).to eq(true)
    end

    it "json" do
      data = '{"a":1}'
      expect(@feature).to receive(:raw_json).and_return(data)
      expect(@ctx.json("feature")).to eq(JSON.parse(data))
    end

    it "raw_json" do
      expect(@feature).to receive(:raw_json).and_return("raw_json")
      expect(@ctx.raw_json("feature")).to eq("raw_json")
    end

    it "enabled?" do
      expect(@feature).to receive(:enabled?).and_return(true)
      expect(@ctx.enabled?("feature")).to eq(true)
    end

    it "set?" do
      expect(@feature).to receive(:set?).and_return(true)
      expect(@ctx.set?("feature")).to eq(true)
    end

    it "exists?" do
      expect(@feature).to receive(:exists?).and_return(true)
      expect(@ctx.exists?("feature")).to eq(true)
    end

    it "gets the feature" do
      expect(@ctx.feature("feature")).to eq(@feature)
    end
  end

  it "can chain" do
    @ctx.build.build_sync
  end
end
