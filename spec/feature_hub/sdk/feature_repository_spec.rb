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
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah"}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
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
      expect(FeatureHub::Sdk::FeatureState).to_not receive(:new)
    end

    it "should try and delete a feature we did create" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah"}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:update_feature_state).with(nil)
      repo.notify("feature", data)
      repo.notify("delete_feature", data)
    end

    it "should allow us to update an existing feature if the version changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah", "version": 1}')
      data2 = JSON.parse('{"key": "blah", "version": 2}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:update_feature_state).with(data2)
      repo.notify("feature", data)
      repo.notify("feature", data2)
    end

    it "should allow us to update the feature if the version is the same but the value changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      data2 = JSON.parse('{"key": "blah", "version": 1, "value": false}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:value).and_return(true)
      expect(fs).to receive(:update_feature_state).with(data2)
      repo.notify("feature", data)
      repo.notify("feature", data2)
    end

    it "should reject the update if the version hasn't changed" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(1).exactly(2).times
      expect(fs).to receive(:value).and_return(true)
      repo.notify("feature", data)
      repo.notify("feature", data)
    end

    it "should reject the update if the new version is less than the existing one" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo, data).and_return(fs)
      expect(fs).to receive(:version).and_return(2).exactly(1).times
      repo.notify("feature", data)
      repo.notify("feature", data)
    end

    it "should allow me to get a feature and then update it with data" do
      fs = instance_double(FeatureHub::Sdk::FeatureState)
      expect(FeatureHub::Sdk::FeatureState).to receive(:new).with(:blah, repo).and_return(fs)
      expect(fs).to receive(:version).and_return(-1).exactly(2).times
      repo.feature("blah")
      data = JSON.parse('{"key": "blah", "version": 1, "value": true}')
      expect(fs).to receive(:update_feature_state).with(data)
      repo.notify("feature", data)
    end
  end
end
