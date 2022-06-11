# frozen_string_literal: true

RSpec.describe FeatureHub::Sdk::ClientEvalFeatureContext do
  describe "client context" do
    let(:repo) { instance_double(FeatureHub::Sdk::InternalFeatureRepository) }
    let(:edge) { instance_double(FeatureHub::Sdk::EdgeService) }
    let(:ctx) {  FeatureHub::Sdk::ClientEvalFeatureContext.new(repo, edge) }

    it "should call poll when we have a context and a build is requested but nothing else" do
      expect(edge).to receive(:poll)
      ctx.user_key("me@me.com").session_key("123 45").attribute_value("pinky", ["ponky"]).build
    end

    it "should do nothing when build_sync is called" do
      ctx.user_key("me@me.com").session_key("123 45").attribute_value("pinky", ["ponky"]).build_sync
    end

    it "should ask for a feature with the current context when asking for a feature" do
      feature = instance_double(FeatureHub::Sdk::FeatureState)
      expect(repo).to receive(:feature).with("fred").and_return(feature)
      expect(feature).to receive(:with_context).with(ctx).and_return(feature)
      ctx.feature("fred")
    end
  end
end
