# frozen_string_literal: true

require "test_helper"

module Grok
  # Contract test for the Grok transport layer: the request it sends (including
  # the CLI-only auth header) and how each failure mode maps onto the error
  # hierarchy.
  class ApiTest < ActiveSupport::TestCase
    test "billing sends the CLI auth header and the session token" do
      request = stub_request(:get, billing_url)
                .with(headers: {
                  "Authorization" => "Bearer token",
                  "X-XAI-Token-Auth" => Grok::Api::GROK_CLI_AUTH_HEADER
                })
                .to_return(status: 200, body: { config: {} }.to_json,
                           headers: { "Content-Type" => "application/json" })

      assert_equal({ "config" => {} }, Api.billing(access_token: "token"))
      assert_requested request
    end

    test "billing passes the stored user id when present" do
      request = stub_request(:get, billing_url)
                .with(headers: { "Authorization" => "Bearer token", "x-userid" => "u-1" })
                .to_return(status: 200, body: { config: {} }.to_json,
                           headers: { "Content-Type" => "application/json" })

      Api.billing(access_token: "token", user_id: "u-1")

      assert_requested request
    end

    test "models reads the CLI proxy's list with the CLI auth header and the session token" do
      request = stub_request(:get, Api::MODELS_URL)
                .with(headers: { "Authorization" => "Bearer token", "X-XAI-Token-Auth" => Api::GROK_CLI_AUTH_HEADER,
                                 "x-userid" => "u-1" })
                .to_return(status: 200, body: { object: "list", data: [ { id: "grok-4.7" } ] }.to_json,
                           headers: { "Content-Type" => "application/json" })

      assert_equal [ { "id" => "grok-4.7" } ], Api.models(access_token: "token", user_id: "u-1")
      assert_requested request
    end

    test "models raises UnauthorizedError on 401" do
      stub_request(:get, Api::MODELS_URL).to_return(status: 401, body: "expired")

      assert_raises(Api::UnauthorizedError) { Api.models(access_token: "token") }
    end

    test "billing raises UnauthorizedError on 401" do
      stub_request(:get, billing_url).to_return(status: 401, body: "expired")

      error = assert_raises(Api::UnauthorizedError) { Api.billing(access_token: "stale") }

      assert_equal 401, error.status
      assert_match(/billing failed: HTTP 401/, error.message)
    end

    test "billing raises HTTPError on any other failure status" do
      stub_request(:get, billing_url).to_return(status: 429, body: "slow")

      error = assert_raises(Api::HTTPError) { Api.billing(access_token: "tok") }

      assert_equal 429, error.status
      refute_kind_of Api::UnauthorizedError, error
    end

    test "billing raises ParseError on a body that is not a JSON object" do
      stub_request(:get, billing_url).to_return(status: 200, body: "not json")
      assert_raises(Api::ParseError) { Api.billing(access_token: "tok") }
    end

    private

    def billing_url
      "#{Api::BILLING_URL}?format=credits"
    end
  end
end
