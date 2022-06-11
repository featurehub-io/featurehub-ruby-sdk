# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::FeatureHubConfig do
  it "api keys should be of a consistent type" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abs*123", "123", "xyz"])
    end.to raise_error(RuntimeError, "api keys must all be of one type")
  end

  it "should ensure edge url is not nil" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new(nil, ["abs*123"])
    end.to raise_error(RuntimeError, "edge_url is not set to a valid string")
  end

  it "should ensure edge url is not empty" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new("", ["abs*123"])
    end.to raise_error(RuntimeError, "edge_url is not set to a valid string")
  end

  it "should ensure api keys are not nil" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", nil)
    end.to raise_error(RuntimeError, "api_keys must be an array of API keys")
  end

  it "should ensure api keys are not empty" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", [])
    end.to raise_error(RuntimeError, "api_keys must be an array of API keys")
  end

  it "should detect client evaluated keys" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abs*123"])
    expect(config.client_evaluated).to eq(true)
  end

  it "should detect server evaluated keys" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abs123"])
    expect(config.client_evaluated).to eq(false)
  end

  it "should ensure edge url ends with a slash" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abs123"])
    expect(config.edge_url.end_with?("/")).to eq(true)
  end

  it "should ensure api keys are preserved" do
    api_keys = %w[abc 123 xyz]
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", api_keys)
    expect(config.api_keys).to eq(api_keys)
  end

  describe "with simple setup" do
    let(:config) { FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", %w[abc 123 xyz]) }

    it "should allow us to replace the repository" do
      repo = config.repository
      mock_repo = instance_double(FeatureHub::Sdk::InternalFeatureRepository)
      config.repository(mock_repo)
      expect(config.repository).to_not eq(repo)
    end

    it "should attempt to set up the edge service on init" do
      edge = instance_double(FeatureHub::Sdk::EdgeService)
      initializer = double
      expect(initializer).to receive(:call).with(config.repository, config.api_keys, config.edge_url).and_return(edge)
      config.edge_service_provider(initializer)

      expect(config.get_or_create_edge_service).to eq(edge)

      expect(edge).to receive(:poll)
      expect(edge).to receive(:close)

      config.init
      config.close
    end

    it "new_context should give us a server context" do
      edge = instance_double(FeatureHub::Sdk::EdgeService)
      config.edge_service_provider(->(_x, _y, _z) { edge })
      context = config.new_context
      expect(context).to be_a FeatureHub::Sdk::ServerEvalFeatureContext
    end
  end

  it "should use a client context with client keys" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc*123"])
    edge = instance_double(FeatureHub::Sdk::EdgeService)
    config.edge_service_provider(->(_x, _y, _z) { edge })
    context = config.new_context
    expect(context).to be_a FeatureHub::Sdk::ClientEvalFeatureContext
  end

  it "should close the previous edge service when swapping" do
    edge1 = instance_double(FeatureHub::Sdk::EdgeService)
    edge2 = instance_double(FeatureHub::Sdk::EdgeService)
    edge_provider = ->(_x, _y, _z) { edge1 }
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc*123"],
                                                   instance_double(FeatureHub::Sdk::FeatureHubRepository),
                                                   edge_provider)
    expect(edge1).to receive(:close)
    config.new_context
    config.edge_service_provider(->(_x, _y, _z) { edge2 })
  end
end
