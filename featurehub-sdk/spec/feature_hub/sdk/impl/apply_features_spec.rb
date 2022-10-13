# frozen_string_literal: true

require "json"

RSpec.describe FeatureHub::Sdk::Impl::ApplyFeature do
  let(:percent) { instance_double(FeatureHub::Sdk::PercentageCalculator) }
  let(:matcher) { instance_double(FeatureHub::Sdk::Impl::MatcherRepository) }
  let(:s_matcher) { instance_double(FeatureHub::Sdk::Impl::StrategyMatcher) }
  let(:context) { instance_double(FeatureHub::Sdk::ClientContext) }
  let(:apply) { FeatureHub::Sdk::Impl::ApplyFeature.new(percent, matcher) }

  before do
    allow(matcher).to receive(:find_matcher).and_return(s_matcher)
  end

  it "should always return false when an undefined context" do
    found = apply.apply([FeatureHub::Sdk::Impl::RolloutStrategy.new({})], "key", "fld", nil)
    expect(found.matched).to eq(false)
    expect(found.value).to eq(nil)
  end

  it "should return false when there are no rollout strategies" do
    found = apply.apply([], "key", "fld", context)
    expect(found.matched).to eq(false)
    expect(found.value).to eq(nil)
  end

  it "should return false when strategies are nil" do
    found = apply.apply(nil, "key", "fld", context)
    expect(found.matched).to eq(false)
    expect(found.value).to eq(nil)
  end

  it "should be false if no strategies match context" do
    expect(context).to receive(:default_percentage_key).and_return("userkey-value")
    expect(context).to receive(:get_attr).with("warehouseId").and_return([])
    json_data = JSON.parse({
      attributes: [
        {
          fieldName: "warehouseId",
          conditional: "INCLUDES",
          values: ["ponsonby"],
          type: "STRING"
        }
      ]
    }.to_json)
    found = apply.apply([FeatureHub::Sdk::Impl::RolloutStrategy.new(json_data)], "FEATURE_NAME", "fld", context)

    expect(found.matched).to eq(false)
    expect(found.value).to eq(nil)
  end

  describe "match receivers" do
    before do
      expect(context).to receive(:default_percentage_key).and_return("userkey-value")
      expect(context).to receive(:get_attr).with("warehouseId").and_return(["ponsonby"])
      json_data = JSON.parse({
        value: "sausage",
        attributes: [
          {
            fieldName: "warehouseId",
            conditional: "INCLUDES",
            values: ["ponsonby"],
            type: "STRING"
          }
        ]
      }.to_json)
      @rsi = FeatureHub::Sdk::Impl::RolloutStrategy.new(json_data)
    end

    it "should not match percentage and should match" do
      expect(s_matcher).to receive(:match).with("ponsonby", @rsi.attributes[0]).and_return(true)
      found = apply.apply([@rsi], "FEATURE_NAME", "fld", context)

      expect(found.matched).to eq(true)
      expect(found.value).to eq("sausage")
    end

    it "should not match the field comparison if the value is different" do
      expect(s_matcher).to receive(:match).with("ponsonby", @rsi.attributes[0]).and_return(false)
      found = apply.apply([@rsi], "FEATURE_NAME", "fld", context)

      expect(found.matched).to eq(false)
      expect(found.value).to eq(nil)
    end
  end

  it "should not extract values ouf of context if there are no percentage attributes" do
    expect(context).to receive(:default_percentage_key).and_return("user@email")
    strategy = instance_double(FeatureHub::Sdk::Impl::RolloutStrategy)
    expect(strategy).to receive(:percentage_attributes?).and_return(false)
    expect(FeatureHub::Sdk::Impl::ApplyFeature.determine_percentage_key(context, strategy)).to eq("user@email")
  end

  it "should extract values ouf of context when calculating percentage" do
    expect(context).to receive(:get_attr).with("a", "<none>").and_return(["one-thing"])
    expect(context).to receive(:get_attr).with("b", "<none>").and_return(["two-thing"])
    strategy = instance_double(FeatureHub::Sdk::Impl::RolloutStrategy)
    expect(strategy).to receive(:percentage_attributes?).and_return(true)
    expect(strategy).to receive(:percentage_attributes).and_return(%w[a b])
    expect(FeatureHub::Sdk::Impl::ApplyFeature.determine_percentage_key(context, strategy)).to eq("one-thing$two-thing")
  end

  it "should ignore a bad percentage request" do
    expect(percent).to receive(:determine_client_percentage).with("userkey", "fid").and_return(21)
    expect(context).to receive(:default_percentage_key).and_return("userkey").at_least(:once)
    json_data = JSON.parse({
      value: "sausage",
      percentage: 20
    }.to_json)

    rsi = FeatureHub::Sdk::Impl::RolloutStrategy.new(json_data)
    found = apply.apply([rsi], "FEATURE_NAME", "fid", context)
    expect(found.matched).to eq(false)
    expect(found.value).to eq(nil)
  end

  describe "it should match out percentages" do
    let(:rsi) do
      json_data = JSON.parse({
        value: "sausage",
        percentage: 20,
        attributes: [
          {
            fieldName: "warehouseId",
            conditional: "INCLUDES",
            values: ["ponsonby"],
            type: "STRING"
          }
        ]
      }.to_json)

      FeatureHub::Sdk::Impl::RolloutStrategy.new(json_data)
    end

    before do
      expect(percent).to receive(:determine_client_percentage).with("userkey", "fid").and_return(15)
      expect(context).to receive(:default_percentage_key).and_return("userkey").at_least(:once)
    end

    # this one is more of an integration test as the strategy matchers are not mocked out
    it "should match percentage and match attributes" do
      expect(context).to receive(:get_attr).with("warehouseId").and_return(["ponsonby"]).at_least(:once)
      apply = FeatureHub::Sdk::Impl::ApplyFeature.new(percent, FeatureHub::Sdk::Impl::MatcherRegistry.new)
      found = apply.apply([rsi], "FEATURE_NAME", "fid", context)
      expect(found.matched).to eq(true)
      expect(found.value).to eq("sausage")
    end

    it "should not match the attribute and hence fail the overall percent match" do
      expect(context).to receive(:get_attr).with("warehouseId").and_return([]).at_least(:once)
      apply = FeatureHub::Sdk::Impl::ApplyFeature.new(percent, FeatureHub::Sdk::Impl::MatcherRegistry.new)
      found = apply.apply([rsi], "FEATURE_NAME", "fid", context)
      expect(found.matched).to eq(false)
      expect(found.value).to eq(nil)
    end
  end

  it "should return false if the supplied value is nil, the attribute value has a value and its an equals comparison" do
    # cond = instance_double(FeatureHub::Sdk::Impl::RolloutStrategyAttributeCondition)
    # expect(cond).to receive(:equals?).and_return(true)
    attr = instance_double(FeatureHub::Sdk::Impl::RolloutStrategyAttribute)
    expect(attr).to receive(:field_name).and_return("userkey").at_least(:once)
    expect(attr).to receive(:values).and_return("fred").at_least(:once) # only one thing needs to be nil
    # expect(attr).to receive(:conditional).and_return(cond)
    rs = instance_double(FeatureHub::Sdk::Impl::RolloutStrategy)
    expect(rs).to receive(:attributes).and_return([attr])

    expect(context).to receive(:get_attr).with("userkey").and_return([])
    expect(apply.match_attribute(context, rs)).to eq(false)
  end

  it "should return true if the supplied and attribute value are null and the condition is equals" do
    cond = instance_double(FeatureHub::Sdk::Impl::RolloutStrategyAttributeCondition)
    expect(cond).to receive(:equals?).and_return(true)
    attr = instance_double(FeatureHub::Sdk::Impl::RolloutStrategyAttribute)
    expect(attr).to receive(:field_name).and_return("userkey").at_least(:once)
    expect(attr).to receive(:values).and_return(nil).at_least(:once) # only one thing needs to be nil
    expect(attr).to receive(:conditional).and_return(cond)
    rs = instance_double(FeatureHub::Sdk::Impl::RolloutStrategy)
    expect(rs).to receive(:attributes).and_return([attr])

    expect(context).to receive(:get_attr).with("userkey").and_return([])
    expect(apply.match_attribute(context, rs)).to eq(true)
  end
end
