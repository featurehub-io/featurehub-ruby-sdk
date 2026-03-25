# frozen_string_literal: true

require "json"
require "redis"

RSpec.describe FeatureHub::Sdk::RedisSessionStore do
  let(:repo) { instance_double(FeatureHub::Sdk::FeatureHubRepository) }
  let(:redis) { instance_double(Redis) }
  let(:timer) { instance_double(Concurrent::TimerTask) }
  let(:prefix) { "featurehub" }
  let(:ids_key) { "#{prefix}_ids" }

  let(:feature) do
    { "id" => "abc-123", "key" => "MY_FLAG", "version" => 1, "type" => "BOOLEAN", "value" => true, "l" => false }
  end

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(Concurrent::TimerTask).to receive(:new).and_return(timer)
    allow(timer).to receive(:execute)
    allow(timer).to receive(:shutdown)
  end

  let(:logger) { instance_double(Logger, debug: nil) }

  def build(options = nil, log = nil)
    described_class.new("redis://localhost:6379", repo, options, log)
  end

  def empty_redis
    allow(redis).to receive(:smembers).with(ids_key).and_return([])
  end

  describe "initialization" do
    it "connects to Redis with the given connection string and default namespace" do
      empty_redis
      expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 0).and_return(redis)
      build
    end

    it "uses the namespace from options" do
      empty_redis
      expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 3).and_return(redis)
      build({ namespace: 3 })
    end

    it "passes the password to Redis when provided" do
      empty_redis
      expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 0, password: "secret").and_return(redis)
      build({ password: "secret" })
    end

    it "does not include password in the Redis options when not provided" do
      empty_redis
      expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 0).and_return(redis)
      build
    end

    it "starts a timer with the configured timeout" do
      empty_redis
      expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 120, run_now: false).and_return(timer)
      expect(timer).to receive(:execute)
      build({ timeout: 120 })
    end

    context "when Redis has no stored features" do
      it "does not notify the repository" do
        empty_redis
        expect(repo).not_to receive(:notify)
        build
      end
    end

    context "when Redis has stored features" do
      before do
        allow(redis).to receive(:smembers).with(ids_key).and_return(["abc-123"])
        allow(redis).to receive(:get).with("#{prefix}_abc-123").and_return(feature.to_json)
      end

      it "loads features and notifies the repository with source redis-store" do
        expect(repo).to receive(:notify).with("features", [feature], "redis-store")
        build
      end

      it "logs a debug message with the feature count" do
        allow(repo).to receive(:notify)
        expect(logger).to receive(:debug).with("[featurehubsdk] loading 1 feature(s) from redis")
        build(nil, logger)
      end

      it "accepts a custom logger" do
        allow(repo).to receive(:notify)
        expect { build(nil, logger) }.not_to raise_error
      end
    end

    context "when Redis has ids but the feature data is missing" do
      before do
        allow(redis).to receive(:smembers).with(ids_key).and_return(["abc-123"])
        allow(redis).to receive(:get).with("#{prefix}_abc-123").and_return(nil)
      end

      it "does not notify the repository" do
        expect(repo).not_to receive(:notify)
        build
      end
    end

    context "when Redis is not available" do
      before do
        allow_any_instance_of(described_class).to receive(:redis_available?).and_return(false)
      end

      it "does not attempt a Redis connection" do
        expect(Redis).not_to receive(:new)
        build
      end

      it "does not notify the repository" do
        expect(repo).not_to receive(:notify)
        build
      end
    end
  end

  describe "default options" do
    before { empty_redis }

    it "defaults namespace to 0" do
      expect(Redis).to receive(:new).with(url: "redis://localhost:6379", db: 0).and_return(redis)
      build
    end

    it "defaults prefix to featurehub" do
      expect(redis).to receive(:smembers).with("featurehub_ids").and_return([])
      build
    end

    it "defaults timeout to 30 seconds" do
      expect(Concurrent::TimerTask).to receive(:new).with(execution_interval: 30, run_now: false).and_return(timer)
      expect(timer).to receive(:execute)
      build
    end
  end

  describe "#process_updates" do
    let(:store) { (empty_redis; build) }

    it "stores each feature in Redis when source is not redis-store" do
      expect(redis).to receive(:get).with("#{prefix}_abc-123").and_return(nil)
      expect(redis).to receive(:sadd).with(ids_key, "abc-123")
      expect(redis).to receive(:set).with("#{prefix}_abc-123", feature.to_json)
      store.process_updates([feature], "streaming")
    end

    it "ignores updates from redis-store source" do
      expect(redis).not_to receive(:set)
      store.process_updates([feature], "redis-store")
    end

    it "stores multiple features" do
      feature2 = feature.merge("id" => "def-456", "key" => "OTHER_FLAG")
      [feature, feature2].each do |f|
        allow(redis).to receive(:get).with("#{prefix}_#{f["id"]}").and_return(nil)
        expect(redis).to receive(:sadd).with(ids_key, f["id"])
        expect(redis).to receive(:set).with("#{prefix}_#{f["id"]}", f.to_json)
      end
      store.process_updates([feature, feature2], "polling")
    end
  end

  describe "#process_update" do
    let(:store) { (empty_redis; build) }

    it "stores the feature in Redis when source is not redis-store" do
      expect(redis).to receive(:get).with("#{prefix}_abc-123").and_return(nil)
      expect(redis).to receive(:sadd).with(ids_key, "abc-123")
      expect(redis).to receive(:set).with("#{prefix}_abc-123", feature.to_json)
      store.process_update(feature, "streaming")
    end

    it "ignores updates from redis-store source" do
      expect(redis).not_to receive(:set)
      store.process_update(feature, "redis-store")
    end

    it "overwrites an older version in Redis" do
      old = feature.merge("version" => 0)
      allow(redis).to receive(:get).with("#{prefix}_abc-123").and_return(old.to_json)
      expect(redis).to receive(:sadd).with(ids_key, "abc-123")
      expect(redis).to receive(:set).with("#{prefix}_abc-123", feature.to_json)
      store.process_update(feature, "polling")
    end

    it "does not overwrite a newer version already in Redis" do
      newer = feature.merge("version" => 99)
      allow(redis).to receive(:get).with("#{prefix}_abc-123").and_return(newer.to_json)
      expect(redis).not_to receive(:set)
      store.process_update(feature, "polling")
    end

    it "does not overwrite the same version already in Redis" do
      allow(redis).to receive(:get).with("#{prefix}_abc-123").and_return(feature.to_json)
      expect(redis).not_to receive(:set)
      store.process_update(feature, "polling")
    end
  end

  describe "#delete_feature" do
    let(:store) { (empty_redis; build) }

    it "removes the feature from Redis" do
      expect(redis).to receive(:srem).with(ids_key, "abc-123")
      expect(redis).to receive(:del).with("#{prefix}_abc-123")
      store.delete_feature(feature, "streaming")
    end

    it "ignores deletes from redis-store source" do
      expect(redis).not_to receive(:srem)
      expect(redis).not_to receive(:del)
      store.delete_feature(feature, "redis-store")
    end

    it "ignores features without an id" do
      expect(redis).not_to receive(:srem)
      store.delete_feature({ "key" => "NO_ID" }, "streaming")
    end
  end

  describe "#close" do
    it "shuts down the timer" do
      empty_redis
      store = build
      expect(timer).to receive(:shutdown)
      store.close
    end

    it "is safe to call twice" do
      empty_redis
      store = build
      expect(timer).to receive(:shutdown).once
      store.close
      store.close
    end
  end

  describe "custom prefix" do
    it "uses the configured prefix for all Redis keys" do
      allow(redis).to receive(:smembers).with("myapp_ids").and_return(["abc-123"])
      allow(redis).to receive(:get).with("myapp_abc-123").and_return(feature.to_json)
      expect(repo).to receive(:notify).with("features", [feature], "redis-store")
      described_class.new("redis://localhost:6379", repo, { prefix: "myapp" })
    end
  end
end
