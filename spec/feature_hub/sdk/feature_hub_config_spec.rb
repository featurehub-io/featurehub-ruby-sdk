# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::FeatureHubConfig do
  it "api keys should be of a consistent type" do
    expect do
      FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abs*123", "123", "xyz"])
    end.to raise_error(RuntimeError, "api keys must all be of one type")
  end

  describe "no-edge mode" do
    it "enters no-edge mode when no url or keys are provided and env vars are absent" do
      config = FeatureHub::Sdk::FeatureHubConfig.new
      aggregate_failures do
        expect(config.edge_url).to be_nil
        expect(config.api_keys).to be_empty
        expect(config.client_evaluated).to eq(false)
      end
    end

    it "enters no-edge mode when url is given but no keys and env vars are absent" do
      config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost")
      expect(config.api_keys).to be_empty
    end

    it "enters no-edge mode when keys are given but no url and env vars are absent" do
      config = FeatureHub::Sdk::FeatureHubConfig.new(nil, ["abc123"])
      expect(config.edge_url).to be_nil
    end

    it "treats an empty string url the same as nil" do
      config = FeatureHub::Sdk::FeatureHubConfig.new("", ["abc123"])
      expect(config.edge_url).to be_nil
    end

    it "init is a no-op and does not raise" do
      config = FeatureHub::Sdk::FeatureHubConfig.new
      expect { config.init }.not_to raise_error
    end

    it "new_context returns a server context backed by a null edge service" do
      config = FeatureHub::Sdk::FeatureHubConfig.new
      expect(config.new_context).to be_a(FeatureHub::Sdk::ServerEvalFeatureContext)
    end
  end

  describe "resolving from environment variables" do
    around do |example|
      orig_url = ENV.fetch("FEATUREHUB_EDGE_URL", nil)
      orig_client = ENV.fetch("FEATUREHUB_CLIENT_API_KEY", nil)
      orig_server = ENV.fetch("FEATUREHUB_SERVER_API_KEY", nil)
      example.run
    ensure
      ENV["FEATUREHUB_EDGE_URL"] = orig_url
      ENV["FEATUREHUB_CLIENT_API_KEY"] = orig_client
      ENV["FEATUREHUB_SERVER_API_KEY"] = orig_server
    end

    it "picks up the edge url from FEATUREHUB_EDGE_URL" do
      ENV["FEATUREHUB_EDGE_URL"] = "http://from-env"
      ENV["FEATUREHUB_CLIENT_API_KEY"] = "abc*123"
      config = FeatureHub::Sdk::FeatureHubConfig.new
      expect(config.edge_url).to eq("http://from-env/")
    end

    it "picks up a client key from FEATUREHUB_CLIENT_API_KEY" do
      ENV["FEATUREHUB_EDGE_URL"] = "http://from-env"
      ENV["FEATUREHUB_CLIENT_API_KEY"] = "abc*123"
      config = FeatureHub::Sdk::FeatureHubConfig.new
      aggregate_failures do
        expect(config.api_keys).to eq(["abc*123"])
        expect(config.client_evaluated).to eq(true)
      end
    end

    it "picks up a server key from FEATUREHUB_SERVER_API_KEY" do
      ENV["FEATUREHUB_EDGE_URL"] = "http://from-env"
      ENV["FEATUREHUB_SERVER_API_KEY"] = "abc123"
      config = FeatureHub::Sdk::FeatureHubConfig.new
      aggregate_failures do
        expect(config.api_keys).to eq(["abc123"])
        expect(config.client_evaluated).to eq(false)
      end
    end

    it "explicit arguments take priority over env vars" do
      ENV["FEATUREHUB_EDGE_URL"] = "http://from-env"
      ENV["FEATUREHUB_CLIENT_API_KEY"] = "env*key"
      config = FeatureHub::Sdk::FeatureHubConfig.new("http://explicit", ["explicit*key"])
      aggregate_failures do
        expect(config.edge_url).to eq("http://explicit/")
        expect(config.api_keys).to eq(["explicit*key"])
      end
    end

    it "enters no-edge mode when env vars are also absent" do
      ENV.delete("FEATUREHUB_EDGE_URL")
      ENV.delete("FEATUREHUB_CLIENT_API_KEY")
      ENV.delete("FEATUREHUB_SERVER_API_KEY")
      config = FeatureHub::Sdk::FeatureHubConfig.new
      expect(config.edge_url).to be_nil
    end
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

  it "delegates register_interceptor to the repository" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc123"])
    interceptor = instance_double(FeatureHub::Sdk::ValueInterceptor)
    expect(config.repository).to receive(:register_interceptor).with(interceptor)
    config.register_interceptor(interceptor)
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
      expect(initializer).to receive(:call).with(config.repository, config.api_keys, config.edge_url,
                                                 anything).and_return(edge)
      config.edge_service_provider(initializer)

      expect(config.get_or_create_edge_service).to eq(edge)

      expect(edge).to receive(:poll)
      expect(edge).to receive(:close)

      config.init
      config.close
    end

    it "new_context should give us a server context" do
      edge = instance_double(FeatureHub::Sdk::EdgeService)
      config.edge_service_provider(->(_x, _y, _z, _l) { edge })
      context = config.new_context
      expect(context).to be_a FeatureHub::Sdk::ServerEvalFeatureContext
    end
  end

  it "should use a client context with client keys" do
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc*123"])
    edge = instance_double(FeatureHub::Sdk::EdgeService)
    config.edge_service_provider(->(_x, _y, _z, _l) { edge })
    context = config.new_context
    expect(context).to be_a FeatureHub::Sdk::ClientEvalFeatureContext
  end

  describe "#value" do
    let(:repo) { instance_double(FeatureHub::Sdk::InternalFeatureRepository) }
    let(:config) { FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc123"], repo) }

    it "delegates to the repository and returns the feature value when present" do
      expect(repo).to receive(:value).with("MY_FLAG", nil, nil).and_return(true)
      expect(config.value("MY_FLAG")).to eq(true)
    end

    it "delegates the default value to the repository" do
      expect(repo).to receive(:value).with("MY_FLAG", false, nil).and_return(false)
      expect(config.value("MY_FLAG", false)).to eq(false)
    end

    it "delegates attrs to the repository" do
      attrs = { country: "nz" }
      expect(repo).to receive(:value).with("MY_FLAG", nil, attrs).and_return("blue")
      expect(config.value("MY_FLAG", nil, attrs)).to eq("blue")
    end
  end

  describe "#environment_id" do
    it "returns the fallback id when no api keys are configured" do
      config = FeatureHub::Sdk::FeatureHubConfig.new
      expect(config.environment_id).to eq("569b0129-d53d-4516-a818-9154af601047")
    end

    it "returns the 1st part when the key has two slash-separated parts" do
      config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["env-id/api-key"])
      expect(config.environment_id).to eq("env-id")
    end

    it "returns the 2nd part when the key has three slash-separated parts" do
      config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["org-id/env-id/api*key"])
      expect(config.environment_id).to eq("env-id")
    end
  end

  it "should close the previous edge service when swapping" do
    edge1 = instance_double(FeatureHub::Sdk::EdgeService)
    edge2 = instance_double(FeatureHub::Sdk::EdgeService)
    edge_provider = ->(_x, _y, _z, _l) { edge1 }
    config = FeatureHub::Sdk::FeatureHubConfig.new("http://localhost", ["abc*123"],
                                                   instance_double(FeatureHub::Sdk::FeatureHubRepository),
                                                   edge_provider)
    expect(edge1).to receive(:close)
    config.new_context
    config.edge_service_provider(->(_x, _y, _z, _l) { edge2 })
  end
end
