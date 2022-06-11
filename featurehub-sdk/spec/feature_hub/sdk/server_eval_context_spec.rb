# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::ServerEvalFeatureContext do
  describe "server context" do
    let(:repo) { instance_double(FeatureHub::Sdk::InternalFeatureRepository) }
    let(:edge) { instance_double(FeatureHub::Sdk::EdgeService) }
    let(:ctx) {  FeatureHub::Sdk::ServerEvalFeatureContext.new(repo, edge) }

    it "should let me set context and they appear as headers" do
      expect(edge).to receive(:context_change).with("user_key=me%40me.com&session=123+45&pinky=ponky")
      expect(repo).to receive(:not_ready!)
      ctx.user_key("me@me.com").session_key("123 45").attribute_value("pinky", ["ponky"]).build
    end

    it "should not change the context once i have set it once with the same data" do
      expect(edge).to receive(:context_change).with("user_key=me")
      expect(repo).to receive(:not_ready!)
      ctx.user_key("me").build
      ctx.build
    end

    it "should not reset the header if the header is empty" do
      expect(edge).to receive(:poll)
      ctx.build
    end

    it "should not reset the header if the header is empty" do
      expect(edge).to receive(:poll)
      ctx.build_sync
    end
  end
end
