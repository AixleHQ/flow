# frozen_string_literal: true

require "test_helper"

module AixleInsights
  class ClientTest < ActiveSupport::TestCase
    setup do
      @base = "https://otel.insights.test"
      @original_base_url = Settings.aixle_insights.base_url
      Settings.aixle_insights.base_url = @base
    end

    teardown do
      Settings.aixle_insights.base_url = @original_base_url
    end

    def logs_url = "#{@base}/v1/logs"

    test "post_logs sends the payload to /v1/logs with the bearer token and JSON content type" do
      stub = stub_request(:post, logs_url)
             .with(
               headers: { "Authorization" => "Bearer company-token", "Content-Type" => "application/json" },
               body: { resourceLogs: [ { foo: "bar" } ] }.to_json
             )
             .to_return(status: 200, body: { partialSuccess: {} }.to_json)

      result = Client.post_logs(payload: { resourceLogs: [ { foo: "bar" } ] }, token: "company-token")

      assert_requested stub
      assert_equal({ "partialSuccess" => {} }, result)
    end

    test "post_logs treats an empty 200 body as accepted" do
      stub_request(:post, logs_url).to_return(status: 200, body: "")

      assert_equal({}, Client.post_logs(payload: { resourceLogs: [] }, token: "t"))
    end

    test "post_logs treats a 200 with an unparseable body as accepted" do
      stub_request(:post, logs_url).to_return(status: 200, body: "not json")

      assert_equal({}, Client.post_logs(payload: { resourceLogs: [] }, token: "t"))
    end

    test "post_logs raises Error carrying the status on a non-2xx response" do
      stub_request(:post, logs_url).to_return(status: 503, body: "upstream down")

      error = assert_raises(Client::Error) do
        Client.post_logs(payload: { resourceLogs: [] }, token: "t")
      end
      assert_match(/503/, error.message)
    end

    test "post_logs raises when the collector base_url is not configured" do
      Settings.aixle_insights.base_url = nil

      assert_raises(Client::Error) do
        Client.post_logs(payload: { resourceLogs: [] }, token: "t")
      end
    end
  end
end
