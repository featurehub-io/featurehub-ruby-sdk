# frozen_string_literal: true

require "json"
require "digest"
require "dalli"

RSpec.describe FeatureHub::Sdk::MemcacheSessionStore do
  let(:repo) { instance_double(FeatureHub::Sdk::FeatureHubRepository) }
  let(:config) { instance_double(FeatureHub::Sdk::FeatureHubConfig) }
  let(:dalli) { instance_double(Dalli::Client) }
  let(:timer) { instance_double(Concurrent::TimerTask) }
  let(:env_id) { "test-env-123" }
  let(:prefix) { "featurehub" }
  let(:features_key) { "#{prefix}_#{env_id}" }
  let(:sha_key) { "#{prefix}_#{env_id}_sha" }

  let(:feature) do
    { "id" => "abc-123", "key" => "MY_FLAG", "version" => 1, "type" => "BOOLEAN", "value" => true }
  end

  before do
    allow(config).to receive(:repository).and_return(repo)
    allow(config).to receive(:environment_id).and_return(env_id)
    allow(Dalli::Client).to receive(:new).and_return(dalli)
    allow(Concurrent::TimerTask).to receive(:new).and_return(timer)
    allow(timer).to receive(:execute)
    allow(timer).to receive(:shutdown)
    # Run the background load synchronously so tests can assert on its effects.
    allow(Concurrent::Future).to receive(:execute) { |&block| block.call }
  end

  def sha_of(features)
    parts = features.map { |f| "#{f["id"]}:#{(f["version"] || 0).to_i}" }.join("|")
    Digest::SHA256.hexdigest(parts)
  end

  def empty_memcache
    allow(dalli).to receive(:get).with(sha_key).and_return(nil)
    allow(dalli).to receive(:get).with(features_key).and_return(nil)
  end

  def build(options = nil)
    described_class.new("localhost:11211", config, options)
  end

  # ---------------------------------------------------------------------------
  describe FeatureHub::Sdk::MemcacheSessionStoreOptions do
    subject(:opts) { described_class.new }

    it { expect(opts.prefix).to eq("featurehub") }
    it { expect(opts.backoff_timeout).to eq(500) }
    it { expect(opts.retry_update_count).to eq(10) }
    it { expect(opts.refresh_timeout).to eq(300) }
    it { expect(opts.logger).to be_nil }

    it "accepts all custom values" do
      logger = instance_double(Logger)
      custom = described_class.new(
        prefix: "myapp",
        backoff_timeout: 100,
        retry_update_count: 3,
        refresh_timeout: 60,
        logger: logger
      )
      aggregate_failures do
        expect(custom.prefix).to eq("myapp")
        expect(custom.backoff_timeout).to eq(100)
        expect(custom.retry_update_count).to eq(3)
        expect(custom.refresh_timeout).to eq(60)
        expect(custom.logger).to eq(logger)
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "initialization" do
    context "when Dalli is available" do
      it "creates a Dalli::Client from a connection string" do
        empty_memcache
        expect(Dalli::Client).to receive(:new).with("localhost:11211", { serializer: JSON }).and_return(dalli)
        build
      end

      it "uses an existing Dalli::Client directly without creating a new one" do
        empty_memcache
        expect(Dalli::Client).not_to receive(:new)
        described_class.new(dalli, config)
      end

      it "starts a timer using the configured refresh_timeout" do
        empty_memcache
        expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 60, run_now: false).and_return(timer)
        expect(timer).to receive(:execute)
        build({ refresh_timeout: 60 })
      end

      it "accepts a MemcacheSessionStoreOptions object directly" do
        opts = FeatureHub::Sdk::MemcacheSessionStoreOptions.new(prefix: "myapp")
        allow(dalli).to receive(:get).with("myapp_#{env_id}_sha").and_return(nil)
        allow(dalli).to receive(:get).with("myapp_#{env_id}").and_return(nil)
        expect { described_class.new("localhost:11211", config, opts) }.not_to raise_error
      end

      context "when memcache is empty" do
        before { empty_memcache }

        it "does not notify the repository" do
          expect(repo).not_to receive(:notify)
          build
        end
      end

      context "when memcache has stored features" do
        before do
          allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
          allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
        end

        it "notifies the repository with stored features and source memcache-store" do
          expect(repo).to receive(:notify).with("features", [feature], "memcache-store")
          build
        end

        it "logs a debug message with the feature count" do
          logger = instance_double(Logger, debug: nil)
          allow(repo).to receive(:notify)
          expect(logger).to receive(:debug).with("[featurehubsdk] loading 1 feature(s) from memcache")
          build({ logger: logger })
        end

        it "does not raise when no logger is configured" do
          allow(repo).to receive(:notify)
          expect { build }.not_to raise_error
        end
      end

      context "when features JSON is corrupt" do
        before do
          allow(dalli).to receive(:get).with(sha_key).and_return(nil)
          allow(dalli).to receive(:get).with(features_key).and_return("not-valid-json{{")
        end

        it "does not notify the repository" do
          expect(repo).not_to receive(:notify)
          build
        end
      end
    end

    context "when Dalli is not available" do
      before { allow_any_instance_of(described_class).to receive(:dalli_available?).and_return(false) }

      it "does not create a Dalli::Client" do
        expect(Dalli::Client).not_to receive(:new)
        build
      end

      it "does not notify the repository" do
        expect(repo).not_to receive(:notify)
        build
      end

      it "does not start a timer" do
        expect(Concurrent::TimerTask).not_to receive(:new)
        build
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "default options" do
    before { empty_memcache }

    it "defaults prefix to featurehub" do
      expect(dalli).to receive(:get).with("featurehub_#{env_id}_sha").and_return(nil)
      expect(dalli).to receive(:get).with("featurehub_#{env_id}").and_return(nil)
      build
    end

    it "defaults refresh_timeout to 300 seconds" do
      expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 300, run_now: false).and_return(timer)
      expect(timer).to receive(:execute)
      build
    end
  end

  # ---------------------------------------------------------------------------
  describe "custom prefix" do
    it "uses the configured prefix for all memcache keys" do
      allow(dalli).to receive(:get).with("myapp_#{env_id}_sha").and_return(sha_of([feature]))
      allow(dalli).to receive(:get).with("myapp_#{env_id}").and_return([feature].to_json)
      expect(repo).to receive(:notify).with("features", [feature], "memcache-store")
      build({ prefix: "myapp" })
    end
  end

  # ---------------------------------------------------------------------------
  describe "#close" do
    before { empty_memcache }
    let!(:store) { build }

    it "shuts down the timer" do
      expect(timer).to receive(:shutdown)
      store.close
    end

    it "is safe to call twice" do
      expect(timer).to receive(:shutdown).once
      store.close
      store.close
    end
  end

  # ---------------------------------------------------------------------------
  describe "timer (check_for_updates)" do
    # Use before + let! so the store is built with nil stubs, then tests can override.
    before { empty_memcache }
    let!(:store) { build }

    it "does nothing when the SHA is unchanged" do
      allow(dalli).to receive(:get).with(sha_key).and_return(nil)
      expect(repo).not_to receive(:notify)
      store.send(:check_for_updates)
    end

    it "reloads and notifies the repository when the SHA has changed" do
      allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(repo).to receive(:notify).with("features", [feature], "memcache-store")
      store.send(:check_for_updates)
    end

    it "updates the internal SHA so a second tick with the same SHA is a no-op" do
      allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      allow(repo).to receive(:notify)
      store.send(:check_for_updates)

      allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      expect(repo).not_to receive(:notify)
      store.send(:check_for_updates)
    end

    it "logs when a change is detected" do
      logger = instance_double(Logger, debug: nil)
      local_store = build({ logger: logger })
      allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      allow(repo).to receive(:notify)
      expect(logger).to receive(:debug).with("[featurehubsdk] detected memcache change, reloading 1 feature(s)")
      local_store.send(:check_for_updates)
    end
  end

  # ---------------------------------------------------------------------------
  describe "#process_updates" do
    before { empty_memcache }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }

    it "ignores updates from the memcache-store source" do
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.process_updates([feature], "memcache-store")
    end

    it "does nothing when the incoming SHA already matches memcache" do
      allow(dalli).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      expect(dalli).not_to receive(:set).with(features_key, anything)
      expect(dalli).not_to receive(:add)
      store.process_updates([feature], "streaming")
    end

    it "does nothing when no incoming features are newer than memcache" do
      allow(dalli).to receive(:get).with(sha_key).and_return(nil)
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.process_updates([feature], "streaming")
    end

    it "logs a warning after exhausting all retries" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 2, backoff_timeout: 0, logger: logger })
      older = feature.merge("version" => 0)
      allow(dalli).to receive(:get).with(sha_key).and_return(nil)
      allow(dalli).to receive(:get).with(features_key).and_return([older].to_json)
      allow(dalli).to receive(:add).and_return(false)
      expect(logger).to receive(:warn).with("[featurehubsdk] failed to update memcache after 2 retries")
      local_store.process_updates([feature], "streaming")
    end

    context "when incoming features are newer (first write — no existing SHA)" do
      let(:older) { feature.merge("version" => 0) }

      before do
        allow(dalli).to receive(:get).with(features_key).and_return([older].to_json)
      end

      it "writes the merged features to the features key" do
        allow(dalli).to receive(:add).and_return(true)
        expect(dalli).to receive(:set).with(features_key, [feature].to_json)
        store.process_updates([feature], "streaming")
      end

      it "atomically claims the SHA key via add" do
        expect(dalli).to receive(:add).with(sha_key, sha_of([feature])).and_return(true)
        allow(dalli).to receive(:set)
        store.process_updates([feature], "streaming")
      end
    end

    context "when incoming features are newer (CAS path — SHA already exists)" do
      let(:older) { feature.merge("version" => 0) }
      let(:existing_sha) { sha_of([older]) }

      # Use a distinct name to avoid shadowing the parent let! and its eager before hook.
      # The let is lazy: stubs are set inside the block so the store is built with them in place.
      let(:cas_store) do
        allow(dalli).to receive(:get).with(sha_key).and_return(existing_sha)
        allow(dalli).to receive(:get).with(features_key).and_return([older].to_json)
        allow(repo).to receive(:notify)
        build({ retry_update_count: 1, backoff_timeout: 0 })
      end

      it "uses CAS to update the SHA key" do
        cas_store # force evaluation so @internal_sha = existing_sha before setting the expectation
        expect(dalli).to receive(:cas).with(sha_key).and_yield(existing_sha).and_return(true)
        allow(dalli).to receive(:set)
        cas_store.process_updates([feature], "streaming")
      end

      it "stores the merged features when CAS succeeds" do
        cas_store # force evaluation
        allow(dalli).to receive(:cas).with(sha_key).and_yield(existing_sha).and_return(true)
        expect(dalli).to receive(:set).with(features_key, [feature].to_json)
        cas_store.process_updates([feature], "streaming")
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#process_update" do
    before { empty_memcache }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }

    it "ignores updates from the memcache-store source" do
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.process_update(feature, "memcache-store")
    end

    it "stores a brand-new feature not present in memcache" do
      allow(dalli).to receive(:get).with(features_key).and_return(nil)
      expect(dalli).to receive(:add).with(sha_key, sha_of([feature])).and_return(true)
      expect(dalli).to receive(:set).with(features_key, [feature].to_json)
      store.process_update(feature, "streaming")
    end

    it "stores the feature when it has a newer version" do
      older = feature.merge("version" => 0)
      allow(dalli).to receive(:get).with(features_key).and_return([older].to_json)
      expect(dalli).to receive(:add).with(sha_key, sha_of([feature])).and_return(true)
      expect(dalli).to receive(:set).with(features_key, [feature].to_json)
      store.process_update(feature, "streaming")
    end

    it "does not store the feature when the version is the same" do
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.process_update(feature, "polling")
    end

    it "does not store the feature when the existing version is newer" do
      newer = feature.merge("version" => 99)
      allow(dalli).to receive(:get).with(features_key).and_return([newer].to_json)
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.process_update(feature, "polling")
    end
  end

  # ---------------------------------------------------------------------------
  describe "#delete_feature" do
    before { empty_memcache }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }

    it "ignores deletes from the memcache-store source" do
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.delete_feature(feature, "memcache-store")
    end

    it "ignores features without an id" do
      expect(dalli).not_to receive(:add)
      store.delete_feature({ "key" => "NO_ID" }, "streaming")
    end

    it "removes the feature and stores the updated list" do
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(dalli).to receive(:add).with(sha_key, sha_of([])).and_return(true)
      expect(dalli).to receive(:set).with(features_key, [].to_json)
      store.delete_feature(feature, "streaming")
    end

    it "does nothing when the feature is not present in memcache" do
      allow(dalli).to receive(:get).with(features_key).and_return([].to_json)
      expect(dalli).not_to receive(:add)
      expect(dalli).not_to receive(:cas)
      store.delete_feature(feature, "streaming")
    end

    it "stops retrying without a warning once the feature is already gone on reload" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 3, backoff_timeout: 0, logger: logger })
      allow(dalli).to receive(:get).with(features_key).and_return([feature].to_json, [].to_json)
      allow(dalli).to receive(:get).with(sha_key).and_return("some-sha")
      expect(logger).not_to receive(:warn)
      local_store.delete_feature(feature, "streaming")
    end
  end

  # ---------------------------------------------------------------------------
  describe "CAS retry: stops early when no longer newer" do
    before { empty_memcache }

    it "does not log a warning when memcache versions overtake the incoming update on reload" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 3, backoff_timeout: 0, logger: logger })
      older = feature.merge("version" => 0)
      newer = feature.merge("version" => 99)
      # Pre-check returns a different SHA so we proceed; each retry sees a SHA mismatch.
      allow(dalli).to receive(:get).with(sha_key).and_return("other-sha")
      # First retry: feature v0 in memcache (ours at v1 is newer).
      # Second retry: feature v99 in memcache (ours at v1 is no longer newer) → block returns nil.
      allow(dalli).to receive(:get).with(features_key).and_return([older].to_json, [newer].to_json)
      allow(dalli).to receive(:add).and_return(false)
      expect(logger).not_to receive(:warn)
      local_store.process_updates([feature], "streaming")
    end
  end
end
