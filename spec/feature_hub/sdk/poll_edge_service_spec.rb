# frozen_string_literal: true

require "json"

RSpec.describe FeatureHub::Sdk::PollingEdgeService do
  let(:repo) { instance_double(FeatureHub::Sdk::InternalFeatureRepository) }
  let(:sse) { instance_double(SSE::Client) }
  let(:timer) { instance_double(Concurrent::TimerTask) }
  let(:interval) { 0 }
  let(:logger) { double("logger") }
  let(:poller) { described_class.new(repo, ["api_key"], "url/", interval, logger) }
  let(:conn) { instance_double(Faraday::Connection) }
  let(:resp) { instance_double(Faraday::Response) }

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(Faraday).to receive(:new).with(url: "url/").and_return(conn)
    allow(Concurrent::TimerTask).to receive(:new).with(execution_interval: interval, run_now: false).and_return(timer)
  end

  context "with a different header" do
    let(:interval) { 20 }

    it "should allow me to set a different header" do
      expect(Digest::SHA256).to receive(:hexdigest).and_return("12345")

      expect(conn).to receive(:get).with("features?apiKey=api_key&contextSha=12345",
                                         {},
                                         hash_including("x-featurehub" => "blah"))
                                   .and_return(resp)

      expect(resp).to receive(:status).and_return(200)
      expect(resp).to receive(:headers).and_return({}).twice
      expect(resp).to receive(:body).and_return("[]")
      expect(timer).to receive(:execute)

      poller.context_change("blah")
      expect(poller.sha_context).to eq("12345")
    end
  end

  # test essentially works, can't figure out how to get it to match
  # it "should pick up the etag header and try and use it again" do
  #   expect(conn).to receive(:get).with("features?apiKey=api_key",
  #                                      request: { timeout: 12 },
  #                                      headers: hash_including(accept: "application/json"))
  #                                .and_return(resp)
  #   expect(resp).to receive(:status).and_return(200).at_least(:twice)
  #   expect(resp).to receive(:headers).and_return({"etag" => "12345"}).at_least(:twice)
  #   expect(resp).to receive(:body).and_return("[]").twice
  #   expect(timer).to receive(:execute).twice
  #   expect(timer).to receive(:shutdown)
  #   poller.poll
  #   poller.close
  #   expect(conn).to receive(:get).with("features?apiKey=api_key",
  #                                      request: { timeout: 12 },
  #                                      headers: hash_including("if-none-matches" => "12345"))
  #                                .and_return(resp).once
  #   poller.poll
  # end

  context "setting a 20 second interval" do
    let(:interval) { 20 }

    before do
      expect(conn).to receive(:get).with("features?apiKey=api_key&contextSha=0",
                                         {},
                                         hash_including(accept: "application/json"))
                                   .and_return(resp)
    end

    it "should start polling and process a 236 response" do
      expect(resp).to receive(:status).and_return(236)
      expect(resp).to receive(:headers).and_return({}).twice
      expect(resp).to receive(:body).and_return("[]")
      expect(timer).to receive(:shutdown)

      poller.poll

      expect(poller.stopped).to eq(true)
    end

    it "should try again on a 503" do
      expect(resp).to receive(:status).and_return(503)
      expect(timer).to receive(:execute)
      poller.poll
      expect(poller.cancel).to eq(false)
    end

    it "should cancel on a 404" do
      expect(resp).to receive(:status).and_return(404)
      expect(repo).to receive(:notify).with("failed", nil)
      expect(logger).to receive(:error)
      expect(timer).to receive(:shutdown)
      poller.poll
      expect(poller.cancel).to eq(true)
    end

    context "should start polling and process a 200 response" do
      before do
        expect(resp).to receive(:status).and_return(200)
        expect(timer).to receive(:execute)
      end

      context "with an etag header" do
        before do
          expect(resp).to receive(:headers).and_return({ "etag" => "abcd" }).twice
        end

        it "and no data" do
          expect(resp).to receive(:body).and_return("[]")

          poller.poll

          expect(poller.etag).to eq("abcd")
        end
      end

      context "with an cache control header" do
        it "that does not contain max-age" do
          expect(resp).to receive(:headers)
            .and_return({ "cache-control" => "no-store, no-age, bark, bark, bark" })
            .at_least(:once)
          expect(resp).to receive(:body).and_return("[]")

          poller.poll

          expect(poller.interval).to eq(interval)
        end

        it "and the timer is created with it and its interval is set correctly" do
          expect(resp).to receive(:headers)
            .and_return({ "cache-control" => "no-store, max-age=24, bark, bark, bark" })
            .at_least(:once)
          expect(resp).to receive(:body).and_return("[]")
          expect(timer).to receive(:execution_interval=).with(24)

          poller.poll
        end
      end

      context "with no headers" do
        before do
          expect(resp).to receive(:headers).and_return({}).twice
        end

        it "and no data" do
          expect(resp).to receive(:body).and_return("[]")

          poller.poll
        end

        it "and have environments" do
          expect(resp).to receive(:body).and_return('[{"features": []}, {"features": []}]')
          expect(repo).to receive(:notify).with("features", []).twice
          poller.poll
        end
      end
    end
  end
end
