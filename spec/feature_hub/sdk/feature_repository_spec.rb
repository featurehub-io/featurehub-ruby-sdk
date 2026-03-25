# frozen_string_literal: true

require "json"

RSpec.describe FeatureHub::Sdk::FeatureHubRepository do
  def raw_good_features
    <<~END_JSON
      [
        {
          "id": "8dbc7ead-55da-4d8e-abb7-2cf7e2e08906",
          "key": "landing_page2",
          "l": true,
          "version": 1,
          "type": "BOOLEAN",
          "value": false
        },
        {
          "id": "25fc2706-8f9b-4e48-926e-4c3fc3321dcc",
          "key": "landing_page",
          "l": false,
          "version": 10,
          "type": "BOOLEAN",
          "value": true
        },
        {
          "id": "32428fd1-c7f4-4691-839e-e8e788ceee37",
          "key": "remote_config",
          "l": false,
          "version": 0,
          "type": "JSON"
        },
        {
          "id": "179a2141-b5d4-41bf-b334-92be7c57fe96",
          "key": "FEATURE_TITLE_TO_UPPERCASE",
          "l": false,
          "version": 37,
          "type": "BOOLEAN",
          "value": true
        },
        {
          "id": "227dc2e8-59e8-424a-b510-328ef52010f7",
          "key": "SUBMIT_COLOR_BUTTON",
          "l": false,
          "version": 28,
          "type": "STRING",
          "value": "orange",
          "strategies": [
            {
              "id": "7000b097-3fcb-4cfb-bd7c-be1640fe0503",
              "value": "green",
              "attributes": [
                {
                  "conditional": "EQUALS",
                  "fieldName": "country",
                  "values": [
                    "australia"
                  ],
                  "type": "STRING"
                }
              ]
            }
          ]
        },
        {
          "id": "34027abd-32f1-4988-9a78-2b81ad468cc6",
          "key": "sample_flag",
          "l": false,
          "version": 2,
          "type": "BOOLEAN",
          "value": true
        }
      ]
    END_JSON
  end

  describe "feature repository" do
    let(:apply_features) { instance_double(FeatureHub::Sdk::Impl::ApplyFeature) }
    let(:repo) { FeatureHub::Sdk::FeatureHubRepository.new(apply_features) }

    it "should receive a json array of features and process it" do
      features = JSON.parse(raw_good_features)

      expect(repo.ready?).to eq(false)
      repo.notify("features", features)
      expect(repo.ready?).to eq(true)

      expect(repo.feature("landing_page2").flag).to eq(false)
      expect(repo.feature("landing_page").flag).to eq(true)
      expect(repo.feature("landing_page2").number).to eq(nil)
      expect(repo.feature("SUBMIT_COLOR_BUTTON").string).to eq("orange")
      expect(repo.feature("SUBMIT_COLOR_BUTTON").number).to eq(nil)

      repo.not_ready!
      expect(repo.ready?).to eq(false)
      expect(repo.extract_feature_state).to eq(features)
    end

    it "should receive a feature creation and correctly evaluate it" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah"}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      repo.notify("feature", data)
      expect(repo.feature("blah")).to eq(fs)
    end

    it "should become not ready if it receives a fail after a success" do
      data = JSON.parse('{"key": "blah"}')
      repo.notify("feature", data)
      expect(repo.ready?).to eq(true)
      repo.notify("failed", nil)
      expect(repo.ready?).to eq(false)
    end

    it "should not try and delete a feature we never created" do
      data = JSON.parse('{"key": "blah"}')
      repo.notify("delete_feature", data)
      expect(FeatureHub::Sdk::FeatureStateHolder).to_not receive(:new)
    end

    it "should try and delete a feature we did create" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah"}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:update_feature_state).with(nil)
      repo.notify("feature", data)
      repo.notify("delete_feature", data)
    end

    it "should allow us to update an existing feature if the version changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah", "version": 1}')
      data2 = JSON.parse('{"key": "blah", "version": 2}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:update_feature_state).with(data2)
      repo.notify("feature", data)
      repo.notify("feature", data2)
    end

    it "should allow us to update the feature if the version is the same but the value changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      data2 = JSON.parse('{"key": "blah", "version": 1, "value": false}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:value).and_return(true)
      expect(fs).to receive(:update_feature_state).with(data2)
      repo.notify("feature", data)
      repo.notify("feature", data2)
    end

    it "should reject the update if the version hasn't changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:value).and_return(true)
      repo.notify("feature", data)
      repo.notify("feature", data)
    end

    it "should reject the update if the new version is less than the existing one" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(2).exactly(1).times
      repo.notify("feature", data)
      repo.notify("feature", data)
    end

    it "should allow me to get a feature and then update it with data" do
      fs = instance_double(FeatureHub::Sdk::FeatureStateHolder)
      expect(FeatureHub::Sdk::FeatureStateHolder).to receive(:new).with(:blah, repo).and_return(fs)
      expect(fs).to receive(:version).and_return(-1).exactly(2).times
      repo.feature("blah")
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(fs).to receive(:update_feature_state).with(data)
      repo.notify("feature", data)
    end
  end

  describe "#feature with attrs" do
    let(:repo) { FeatureHub::Sdk::FeatureHubRepository.new }

    before do
      repo.notify("features", [{ "id" => "abc", "key" => "SUBMIT_COLOR_BUTTON", "version" => 1,
                                 "type" => "STRING", "value" => "orange", "l" => false,
                                 "strategies" => [{ "id" => "s1", "value" => "green",
                                                    "attributes" => [{ "conditional" => "EQUALS",
                                                                       "fieldName" => "country",
                                                                       "values" => ["nz"],
                                                                       "type" => "STRING" }] }] }])
    end

    it "returns the default value when attrs do not match any strategy" do
      expect(repo.feature("SUBMIT_COLOR_BUTTON", { country: "au" }).string).to eq("orange")
    end

    it "returns the strategy value when attrs match" do
      expect(repo.feature("SUBMIT_COLOR_BUTTON", { country: "nz" }).string).to eq("green")
    end

    it "behaves the same as calling feature without attrs when attrs is nil" do
      expect(repo.feature("SUBMIT_COLOR_BUTTON", nil).string).to eq("orange")
    end
  end

  describe "#value" do
    let(:repo) { FeatureHub::Sdk::FeatureHubRepository.new }

    before do
      repo.notify("features", [
                    { "id" => "abc", "key" => "MY_STRING", "version" => 1,
                      "type" => "STRING", "value" => "hello", "l" => false },
                    { "id" => "def", "key" => "MY_FLAG", "version" => 1,
                      "type" => "BOOLEAN", "value" => true, "l" => false },
                    { "id" => "ghi", "key" => "COLOR", "version" => 1,
                      "type" => "STRING", "value" => "red", "l" => false,
                      "strategies" => [{ "id" => "s1", "value" => "blue",
                                         "attributes" => [{ "conditional" => "EQUALS",
                                                            "fieldName" => "country",
                                                            "values" => ["nz"],
                                                            "type" => "STRING" }] }] }
                  ])
    end

    it "returns the feature value when the feature is present" do
      expect(repo.value("MY_STRING")).to eq("hello")
    end

    it "returns a boolean feature value" do
      expect(repo.value("MY_FLAG")).to eq(true)
    end

    it "returns nil when the feature does not exist and no default is given" do
      expect(repo.value("UNKNOWN")).to be_nil
    end

    it "returns the default value when the feature does not exist" do
      expect(repo.value("UNKNOWN", "fallback")).to eq("fallback")
    end

    it "returns the feature value even when a default is provided and the feature is present" do
      expect(repo.value("MY_STRING", "fallback")).to eq("hello")
    end

    it "returns the matched strategy value when attrs match" do
      expect(repo.value("COLOR", nil, { country: "nz" })).to eq("blue")
    end

    it "returns the default feature value when attrs do not match any strategy" do
      expect(repo.value("COLOR", nil, { country: "au" })).to eq("red")
    end

    it "returns the caller default when feature is absent and attrs are provided" do
      expect(repo.value("UNKNOWN", "default", { country: "nz" })).to eq("default")
    end
  end

  describe "RawUpdateFeatureListener" do
    let(:repo) { FeatureHub::Sdk::FeatureHubRepository.new }
    let(:listener) { instance_double(FeatureHub::Sdk::RawUpdateFeatureListener) }

    before do
      allow(Concurrent::Future).to receive(:execute) { |&block| block.call }
      repo.register_raw_update_listener(listener)
    end

    it "calls process_updates on listeners when features are received" do
      features = JSON.parse('[{"key": "flag", "version": 1, "type": "BOOLEAN", "value": true}]')
      expect(listener).to receive(:process_updates).with(features, "streaming")
      repo.notify("features", features, "streaming")
    end

    it "calls process_update on listeners when a single feature is received" do
      data = JSON.parse('{"key": "flag", "version": 1, "type": "BOOLEAN", "value": true}')
      expect(listener).to receive(:process_update).with(data, "polling")
      repo.notify("feature", data, "polling")
    end

    it "calls delete_feature on listeners when a feature is deleted" do
      data = JSON.parse('{"key": "flag"}')
      expect(listener).to receive(:delete_feature).with(data, "streaming")
      repo.notify("delete_feature", data, "streaming")
    end

    it "passes the default source of unknown when no source is given" do
      features = JSON.parse('[{"key": "flag", "version": 1, "type": "BOOLEAN", "value": true}]')
      expect(listener).to receive(:process_updates).with(features, "unknown")
      repo.notify("features", features)
    end

    it "notifies all registered listeners" do
      listener2 = instance_double(FeatureHub::Sdk::RawUpdateFeatureListener)
      repo.register_raw_update_listener(listener2)
      features = JSON.parse('[{"key": "flag", "version": 1, "type": "BOOLEAN", "value": true}]')
      expect(listener).to receive(:process_updates).with(features, "polling")
      expect(listener2).to receive(:process_updates).with(features, "polling")
      repo.notify("features", features, "polling")
    end

    it "does not call listeners when status is failed" do
      expect(listener).not_to receive(:process_updates)
      expect(listener).not_to receive(:process_update)
      expect(listener).not_to receive(:delete_feature)
      repo.notify("failed", nil)
    end

    it "calls close on all listeners when the repository is closed" do
      expect(listener).to receive(:close)
      repo.close
    end
  end
end
