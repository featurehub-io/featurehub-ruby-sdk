# frozen_string_literal: true

require "json"
require "digest"
require "redis"

RSpec.describe FeatureHub::Sdk::RedisSessionStore do
  let(:repo) { instance_double(FeatureHub::Sdk::FeatureHubRepository) }
  let(:config) { instance_double(FeatureHub::Sdk::FeatureHubConfig) }
  let(:redis) { instance_double(Redis) }
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
    allow(config).to receive(:register_raw_update_listener)
    allow(Redis).to receive(:new).and_return(redis)
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

  def empty_redis
    allow(redis).to receive(:get).with(sha_key).and_return(nil)
    allow(redis).to receive(:get).with(features_key).and_return(nil)
  end

  def build(options = nil)
    described_class.new("redis://localhost:6379", config, options)
  end

  # ---------------------------------------------------------------------------
  describe FeatureHub::Sdk::RedisSessionStoreOptions do
    subject(:opts) { described_class.new }

    it { expect(opts.prefix).to eq("featurehub") }
    it { expect(opts.backoff_timeout).to eq(500) }
    it { expect(opts.retry_update_count).to eq(10) }
    it { expect(opts.refresh_timeout).to eq(300) }
    it { expect(opts.logger).to be_nil }
    it { expect(opts.db).to eq(0) }

    it "accepts all custom values" do
      logger = instance_double(Logger)
      custom = described_class.new(
        prefix: "myapp",
        backoff_timeout: 100,
        retry_update_count: 3,
        refresh_timeout: 60,
        logger: logger,
        db: 2
      )
      aggregate_failures do
        expect(custom.prefix).to eq("myapp")
        expect(custom.backoff_timeout).to eq(100)
        expect(custom.retry_update_count).to eq(3)
        expect(custom.refresh_timeout).to eq(60)
        expect(custom.logger).to eq(logger)
        expect(custom.db).to eq(2)
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "initialization" do
    context "when Redis is available" do
      it "creates a Redis client from a connection string with default db" do
        empty_redis
        expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 0).and_return(redis)
        build
      end

      it "uses the configured db index" do
        empty_redis
        expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 3).and_return(redis)
        build({ db: 3 })
      end

      it "uses an existing Redis client directly without creating a new one" do
        empty_redis
        expect(Redis).not_to receive(:new)
        described_class.new(redis, config)
      end

      it "starts a timer using the configured refresh_timeout" do
        empty_redis
        expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 60, run_now: false).and_return(timer)
        expect(timer).to receive(:execute)
        build({ refresh_timeout: 60 })
      end

      it "accepts a RedisSessionStoreOptions object directly" do
        opts = FeatureHub::Sdk::RedisSessionStoreOptions.new(prefix: "myapp")
        allow(redis).to receive(:get).with("myapp_#{env_id}_sha").and_return(nil)
        allow(redis).to receive(:get).with("myapp_#{env_id}").and_return(nil)
        expect { described_class.new("redis://localhost:6379", config, opts) }.not_to raise_error
      end

      it "registers itself as a raw update listener with the config" do
        empty_redis
        expect(config).to receive(:register_raw_update_listener).with(instance_of(described_class))
        build
      end

      context "when Redis is empty" do
        before { empty_redis }

        it "does not notify the repository" do
          expect(repo).not_to receive(:notify)
          build
        end
      end

      context "when Redis has stored features" do
        before do
          allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
          allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
        end

        it "notifies the repository with stored features and source redis-store" do
          expect(repo).to receive(:notify).with("features", [feature], "redis-store")
          build
        end

        it "logs a debug message with the feature count" do
          logger = instance_double(Logger, debug: nil)
          allow(repo).to receive(:notify)
          expect(logger).to receive(:debug).with("[featurehubsdk] loading 1 feature(s) from redis")
          build({ logger: logger })
        end

        it "does not raise when no logger is configured" do
          allow(repo).to receive(:notify)
          expect { build }.not_to raise_error
        end
      end

      context "when features JSON is corrupt" do
        before do
          allow(redis).to receive(:get).with(sha_key).and_return(nil)
          allow(redis).to receive(:get).with(features_key).and_return("not-valid-json{{")
        end

        it "does not notify the repository" do
          expect(repo).not_to receive(:notify)
          build
        end
      end
    end

    context "when Redis is not available" do
      before { allow_any_instance_of(described_class).to receive(:redis_available?).and_return(false) }

      it "does not create a Redis client" do
        expect(Redis).not_to receive(:new)
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
    before { empty_redis }

    it "defaults prefix to featurehub" do
      expect(redis).to receive(:get).with("featurehub_#{env_id}_sha").and_return(nil)
      expect(redis).to receive(:get).with("featurehub_#{env_id}").and_return(nil)
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
    it "uses the configured prefix for all Redis keys" do
      allow(redis).to receive(:get).with("myapp_#{env_id}_sha").and_return(sha_of([feature]))
      allow(redis).to receive(:get).with("myapp_#{env_id}").and_return([feature].to_json)
      expect(repo).to receive(:notify).with("features", [feature], "redis-store")
      build({ prefix: "myapp" })
    end
  end

  # ---------------------------------------------------------------------------
  describe "#close" do
    before { empty_redis }
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
    before { empty_redis }
    let!(:store) { build }

    it "does nothing when the SHA is unchanged" do
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      expect(repo).not_to receive(:notify)
      store.send(:check_for_updates)
    end

    it "reloads and notifies the repository when the SHA has changed" do
      allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(repo).to receive(:notify).with("features", [feature], "redis-store")
      store.send(:check_for_updates)
    end

    it "updates the internal SHA so a second tick with the same SHA is a no-op" do
      allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      allow(repo).to receive(:notify)
      store.send(:check_for_updates)

      allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      expect(repo).not_to receive(:notify)
      store.send(:check_for_updates)
    end

    it "logs when a change is detected" do
      logger = instance_double(Logger, debug: nil)
      local_store = build({ logger: logger })
      allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      allow(repo).to receive(:notify)
      expect(logger).to receive(:debug).with("[featurehubsdk] detected redis change, reloading 1 feature(s)")
      local_store.send(:check_for_updates)
    end
  end

  # ---------------------------------------------------------------------------
  describe "#process_updates" do
    before { empty_redis }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }

    it "ignores updates from the redis-store source" do
      expect(redis).not_to receive(:watch)
      expect(redis).not_to receive(:multi)
      store.process_updates([feature], "redis-store")
    end

    it "does nothing when the incoming SHA already matches Redis" do
      allow(redis).to receive(:get).with(sha_key).and_return(sha_of([feature]))
      expect(redis).not_to receive(:watch)
      store.process_updates([feature], "streaming")
    end

    it "does nothing when no incoming features are newer than Redis" do
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(redis).not_to receive(:watch)
      store.process_updates([feature], "streaming")
    end

    it "logs a warning after exhausting all retries" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 2, backoff_timeout: 0, logger: logger })
      older = feature.merge("version" => 0)
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
      allow(redis).to receive(:watch)
      allow(redis).to receive(:multi).and_return(nil) # WATCH fires every time
      allow(redis).to receive(:unwatch)
      expect(logger).to receive(:warn).with("[featurehubsdk] failed to update redis after 2 retries")
      local_store.process_updates([feature], "streaming")
    end

    context "when incoming features are newer (first write — no existing SHA)" do
      let(:older) { feature.merge("version" => 0) }
      let(:tx) { double("redis_tx") }

      before do
        allow(redis).to receive(:get).with(sha_key).and_return(nil)
        allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
        allow(redis).to receive(:watch)
        allow(tx).to receive(:set)
        allow(redis).to receive(:multi).and_yield(tx).and_return(%w[OK OK])
      end

      it "atomically writes the merged features and new SHA via MULTI/EXEC" do
        expect(tx).to receive(:set).with(features_key, [feature].to_json)
        expect(tx).to receive(:set).with(sha_key, sha_of([feature]))
        store.process_updates([feature], "streaming")
      end

      it "issues WATCH on the sha key before attempting the transaction" do
        expect(redis).to receive(:watch).with(sha_key)
        store.process_updates([feature], "streaming")
      end
    end

    context "when incoming features are newer (WATCH detected concurrent change)" do
      let(:older) { feature.merge("version" => 0) }
      let(:existing_sha) { sha_of([older]) }
      let(:tx) { double("redis_tx") }

      # Build a store whose @internal_sha is already set to existing_sha.
      let(:watch_store) do
        allow(redis).to receive(:get).with(sha_key).and_return(existing_sha)
        allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
        allow(repo).to receive(:notify)
        build({ retry_update_count: 1, backoff_timeout: 0 })
      end

      it "uses WATCH + MULTI to update both keys atomically" do
        watch_store # force evaluation so @internal_sha = existing_sha

        allow(redis).to receive(:get).with(sha_key).and_return(existing_sha)
        allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
        allow(redis).to receive(:watch)
        allow(tx).to receive(:set)
        expect(redis).to receive(:multi).and_yield(tx).and_return(%w[OK OK])
        watch_store.process_updates([feature], "streaming")
      end

      it "aborts gracefully when MULTI/EXEC returns nil (concurrent write)" do
        watch_store # force evaluation

        allow(redis).to receive(:get).with(sha_key).and_return(existing_sha)
        allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
        allow(redis).to receive(:watch)
        # EXEC returns nil — a concurrent writer committed between our WATCH and EXEC
        allow(redis).to receive(:multi).and_return(nil)
        expect { watch_store.process_updates([feature], "streaming") }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#process_update" do
    before { empty_redis }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }
    let(:tx) { double("redis_tx") }

    it "ignores updates from the redis-store source" do
      expect(redis).not_to receive(:watch)
      store.process_update(feature, "redis-store")
    end

    it "stores a brand-new feature not present in Redis" do
      allow(redis).to receive(:get).with(features_key).and_return(nil)
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      allow(redis).to receive(:watch)
      allow(tx).to receive(:set)
      expect(redis).to receive(:multi).and_yield(tx).and_return(%w[OK OK])
      store.process_update(feature, "streaming")
    end

    it "stores the feature when it has a newer version" do
      older = feature.merge("version" => 0)
      allow(redis).to receive(:get).with(features_key).and_return([older].to_json)
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      allow(redis).to receive(:watch)
      allow(tx).to receive(:set)
      expect(redis).to receive(:multi).and_yield(tx).and_return(%w[OK OK])
      store.process_update(feature, "streaming")
    end

    it "does not store the feature when the version is the same" do
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      expect(redis).not_to receive(:watch)
      store.process_update(feature, "polling")
    end

    it "does not store the feature when the existing version is newer" do
      newer = feature.merge("version" => 99)
      allow(redis).to receive(:get).with(features_key).and_return([newer].to_json)
      expect(redis).not_to receive(:watch)
      store.process_update(feature, "polling")
    end
  end

  # ---------------------------------------------------------------------------
  describe "#delete_feature" do
    before { empty_redis }
    let!(:store) { build({ retry_update_count: 1, backoff_timeout: 0 }) }
    let(:tx) { double("redis_tx") }

    it "ignores deletes from the redis-store source" do
      expect(redis).not_to receive(:watch)
      store.delete_feature(feature, "redis-store")
    end

    it "ignores features without an id" do
      expect(redis).not_to receive(:watch)
      store.delete_feature({ "key" => "NO_ID" }, "streaming")
    end

    it "removes the feature and stores the updated list atomically" do
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json)
      allow(redis).to receive(:get).with(sha_key).and_return(nil)
      allow(redis).to receive(:watch)
      allow(tx).to receive(:set)
      expect(redis).to receive(:multi).and_yield(tx).and_return(%w[OK OK])
      expect(tx).to receive(:set).with(features_key, [].to_json)
      store.delete_feature(feature, "streaming")
    end

    it "does nothing when the feature is not present in Redis" do
      allow(redis).to receive(:get).with(features_key).and_return([].to_json)
      expect(redis).not_to receive(:watch)
      store.delete_feature(feature, "streaming")
    end

    it "stops retrying without a warning once the feature is already gone on reload" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 3, backoff_timeout: 0, logger: logger })
      # First read: feature present; second read (on retry): feature already gone
      allow(redis).to receive(:get).with(features_key).and_return([feature].to_json, [].to_json)
      allow(redis).to receive(:get).with(sha_key).and_return("some-sha")
      expect(logger).not_to receive(:warn)
      local_store.delete_feature(feature, "streaming")
    end
  end

  # ---------------------------------------------------------------------------
  describe "WATCH retry: stops early when no longer newer" do
    before { empty_redis }

    it "does not log a warning when Redis versions overtake the incoming update on reload" do
      logger = instance_double(Logger, debug: nil, warn: nil)
      local_store = build({ retry_update_count: 3, backoff_timeout: 0, logger: logger })
      older = feature.merge("version" => 0)
      newer = feature.merge("version" => 99)
      # Pre-check returns a different SHA so we proceed; each retry sees a SHA mismatch.
      allow(redis).to receive(:get).with(sha_key).and_return("other-sha")
      # First retry: feature v0 in Redis (ours at v1 is newer).
      # Second retry: feature v99 in Redis (ours at v1 is no longer newer) → block returns nil.
      allow(redis).to receive(:get).with(features_key).and_return([older].to_json, [newer].to_json)
      allow(redis).to receive(:watch)
      allow(redis).to receive(:multi).and_return(nil)
      expect(logger).not_to receive(:warn)
      local_store.process_updates([feature], "streaming")
    end
  end
end
