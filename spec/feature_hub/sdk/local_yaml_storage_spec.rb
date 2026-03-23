# frozen_string_literal: true

require "tempfile"
require "yaml"

RSpec.describe FeatureHub::Sdk::LocalYamlStorage do
  let(:repo) { instance_double(FeatureHub::Sdk::FeatureHubRepository) }

  def with_yaml_file(content)
    file = Tempfile.new(["featurehub-features", ".yaml"])
    file.write(content)
    file.close
    yield file.path
  ensure
    file.unlink
  end

  def build(filename)
    FeatureHub::Sdk::LocalYamlStorage.new(repo, filename)
  end

  describe "when file does not exist" do
    it "does not call notify on the repository" do
      expect(repo).not_to receive(:notify)
      build("/nonexistent-featurehub.yaml")
    end
  end

  describe "when file exists" do
    it "calls notify with source local-yaml and marks the repo ready" do
      with_yaml_file("flagValues:\n  MY_FLAG: true\n") do |path|
        expect(repo).to receive(:notify) do |status, features, source|
          expect(status).to eq("features")
          expect(source).to eq("local-yaml")
          expect(features.length).to eq(1)
        end
        build(path)
      end
    end

    it "reads the yaml file path from FEATUREHUB_LOCAL_YAML env var" do
      with_yaml_file("flagValues:\n  FLAG: true\n") do |path|
        allow(ENV).to receive(:fetch).with("FEATUREHUB_LOCAL_YAML", "featurehub-features.yaml").and_return(path)
        expect(repo).to receive(:notify).with("features", anything, "local-yaml")
        FeatureHub::Sdk::LocalYamlStorage.new(repo)
      end
    end

    it "calls notify with an empty array when flagValues is empty" do
      with_yaml_file("flagValues:\n") do |path|
        expect(repo).to receive(:notify).with("features", [], "local-yaml")
        build(path)
      end
    end

    describe "feature state shape" do
      def captured_features(yaml)
        features = nil
        with_yaml_file(yaml) do |path|
          allow(repo).to receive(:notify) { |_, f, _| features = f }
          build(path)
        end
        features
      end

      it "sets version to 1, l to false, and a consistent environmentId across features" do
        fs = captured_features("flagValues:\n  A: true\n  B: false\n")
        aggregate_failures do
          expect(fs.length).to eq(2)
          fs.each do |f|
            expect(f["version"]).to eq(1)
            expect(f["l"]).to eq(false)
            expect(f["environmentId"]).to be_a(String).and(match(/\A[0-9a-f-]{36}\z/))
          end
          expect(fs[0]["environmentId"]).to eq(fs[1]["environmentId"])
        end
      end

      it "generates a unique id per feature" do
        fs = captured_features("flagValues:\n  A: true\n  B: true\n")
        expect(fs[0]["id"]).not_to eq(fs[1]["id"])
      end

      it "sets key from the yaml key" do
        fs = captured_features("flagValues:\n  MY_FLAG: true\n")
        expect(fs[0]["key"]).to eq("MY_FLAG")
      end

      it "detects boolean type and preserves value" do
        fs = captured_features("flagValues:\n  FLAG: true\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::BOOLEAN)
        expect(fs[0]["value"]).to eq(true)
      end

      it "detects boolean false" do
        fs = captured_features("flagValues:\n  FLAG: false\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::BOOLEAN)
        expect(fs[0]["value"]).to eq(false)
      end

      it "detects string type" do
        fs = captured_features("flagValues:\n  STR: hello\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::STRING)
        expect(fs[0]["value"]).to eq("hello")
      end

      it "detects number type and casts integer to float" do
        fs = captured_features("flagValues:\n  NUM: 42\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::NUMBER)
        expect(fs[0]["value"]).to eq(42.0)
        expect(fs[0]["value"]).to be_a(Float)
      end

      it "detects number type for floats" do
        fs = captured_features("flagValues:\n  NUM: 3.14\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::NUMBER)
        expect(fs[0]["value"]).to eq(3.14)
      end

      it "detects JSON type for complex values and serialises to a JSON string" do
        fs = captured_features("flagValues:\n  CFG:\n    colour: red\n    size: 5\n")
        expect(fs[0]["type"]).to eq(FeatureHub::Sdk::FeatureValueType::JSON)
        parsed = JSON.parse(fs[0]["value"])
        expect(parsed["colour"]).to eq("red")
        expect(parsed["size"]).to eq(5)
      end
    end

    describe "as a RawUpdateFeatureListener" do
      it "ignores process_updates" do
        with_yaml_file("flagValues:\n  F: true\n") do |path|
          allow(repo).to receive(:notify)
          storage = build(path)
          expect { storage.process_updates([], "streaming") }.not_to raise_error
        end
      end

      it "ignores process_update" do
        with_yaml_file("flagValues:\n  F: true\n") do |path|
          allow(repo).to receive(:notify)
          storage = build(path)
          expect { storage.process_update({}, "polling") }.not_to raise_error
        end
      end

      it "ignores delete_feature" do
        with_yaml_file("flagValues:\n  F: true\n") do |path|
          allow(repo).to receive(:notify)
          storage = build(path)
          expect { storage.delete_feature({}, "streaming") }.not_to raise_error
        end
      end

      it "close is a no-op" do
        with_yaml_file("flagValues:\n  F: true\n") do |path|
          allow(repo).to receive(:notify)
          storage = build(path)
          expect { storage.close }.not_to raise_error
        end
      end
    end
  end
end
