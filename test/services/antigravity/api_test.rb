# frozen_string_literal: true

require "test_helper"

module Antigravity
  # Contract test for the Antigravity transport layer: the request it sends,
  # the shape it returns, and how each failure mode maps onto ApiError.
  class ApiTest < ActiveSupport::TestCase
    test "models sends the bearer token and the consumer project body" do
      request = stub_request(:post, Api::MODELS_URL)
                .with(
                  headers: { "Authorization" => "Bearer tok-123", "Content-Type" => "application/json" },
                  body: { project: Api::CONSUMER_PROJECT }.to_json
                )
                .to_return(status: 200, body: { models: {} }.to_json)

      Api.models(access_token: "tok-123")

      assert_requested request
    end

    test "models returns the parsed JSON response body" do
      stub_request(:post, Api::MODELS_URL).to_return(
        status: 200,
        body: { models: { "gemini-pro-agent" => { displayName: "Gemini Pro" } } }.to_json
      )

      body = Api.models(access_token: "tok-123")

      assert_equal({ "gemini-pro-agent" => { "displayName" => "Gemini Pro" } }, body["models"])
    end

    test "models decodes a gzip-compressed response" do
      payload = { models: { "gemini-pro-agent" => { displayName: "Gemini Pro" } } }.to_json
      compressed = StringIO.new
      Zlib::GzipWriter.wrap(compressed) { |gzip| gzip.write(payload) }
      stub_request(:post, Api::MODELS_URL)
        .to_return(status: 200, body: compressed.string, headers: { "Content-Encoding" => "gzip" })

      body = Api.models(access_token: "tok-123")

      assert_equal "Gemini Pro", body.dig("models", "gemini-pro-agent", "displayName")
    end

    test "models raises ApiError on a non-success response" do
      stub_request(:post, Api::MODELS_URL).to_return(status: 401)

      error = assert_raises(Api::ApiError) { Api.models(access_token: "expired") }
      assert_match(/HTTP 401/, error.message)
    end

    test "models raises ApiError on an invalid JSON response" do
      stub_request(:post, Api::MODELS_URL).to_return(status: 200, body: "not json")

      assert_raises(Api::ApiError) { Api.models(access_token: "tok-123") }
    end

    test "models raises ApiError on a transport failure" do
      stub_request(:post, Api::MODELS_URL).to_timeout

      assert_raises(Api::ApiError) { Api.models(access_token: "tok-123") }
    end
  end
end
