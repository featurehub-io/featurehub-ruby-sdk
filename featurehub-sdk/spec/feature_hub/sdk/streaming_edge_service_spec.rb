# frozen_string_literal: true

require "json"

RSpec.describe FeatureHub::Sdk::StreamingEdgeService do
  let(:repo) { instance_double(FeatureHub::Sdk::InternalFeatureRepository) }
  let(:sse) { instance_double(SSE::Client) }
  let(:streaming) { FeatureHub::Sdk::StreamingEdgeService.new(repo, ["api_key"], "url") }

  before do
    expect(SSE::Client).to receive(:new).with("url/features/api_key").and_yield(sse).and_return(sse)
  end

  it "should notify the repository with the command and json data it is passed if it returns a 200" do
    raw_json_data = '[{"id": 1}]'
    json_data = JSON.parse(raw_json_data)
    ok_event = SSE::StreamEvent.new("features", raw_json_data, "1", "etag-last-event-id")
    expect(sse).to receive(:on_event).and_yield(ok_event)
    expect(sse).to receive(:on_error)
    expect(repo).to receive(:notify).with("features", json_data)
    streaming.poll
    expect(streaming.active).to eq(true)
  end

  it "should ignore a normal error" do
    expect(sse).to receive(:on_event)
    error = SSE::Errors::HTTPStatusError.new(503, "some message")
    expect(sse).to receive(:on_error).and_yield(error)

    streaming.poll
    expect(streaming.active).to eq(true)
  end

  it "should stop polling on a 404" do
    expect(repo).to receive(:notify).with("failure", nil)
    expect(sse).to receive(:on_event)
    error = SSE::Errors::HTTPStatusError.new(404, "some message")
    expect(sse).to receive(:on_error).and_yield(error)

    streaming.poll
    expect(streaming.active).to eq(false)
  end
end
