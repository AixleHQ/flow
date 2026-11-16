# frozen_string_literal: true

require "test_helper"

module Cursor
  # Contract test for the Cursor transport layer: the request it sends, the
  # WorkOS session cookie it builds, and how each failure mode maps onto the
  # error hierarchy.
  class ApiTest < ActiveSupport::TestCase
    test "usage_summary builds the WorkOS session cookie from the token's sub claim" do
      token = jwt_with_sub("auth0|user_123")
      cookie = "WorkosCursorSessionToken=auth0%7Cuser_123%3A%3A#{token}"

      request = stub_request(:get, Api::USAGE_SUMMARY_URL)
                .with(headers: {
                  "Cookie" => cookie,
                  "Origin" => Api::DASHBOARD_ORIGIN,
                  "Referer" => "#{Api::DASHBOARD_ORIGIN}/dashboard"
                })
                .to_return(status: 200, body: { individualUsage: {} }.to_json,
                           headers: { "Content-Type" => "application/json" })

      assert_equal({ "individualUsage" => {} }, Api.usage_summary(access_token: token))
      assert_requested request
    end

    test "usage_summary raises UnauthorizedError on 401 so the caller can signal re-auth" do
      stub_request(:get, Api::USAGE_SUMMARY_URL).to_return(status: 401, body: "expired")

      error = assert_raises(Api::UnauthorizedError) { Api.usage_summary(access_token: "stale") }

      assert_equal 401, error.status
      assert_equal "expired", error.body
      assert_match(/usage_summary failed: HTTP 401/, error.message)
    end

    test "usage_summary raises HTTPError on any other failure status" do
      stub_request(:get, Api::USAGE_SUMMARY_URL).to_return(status: 500, body: "boom")

      error = assert_raises(Api::HTTPError) { Api.usage_summary(access_token: "tok") }

      assert_equal 500, error.status
      refute_kind_of Api::UnauthorizedError, error
    end

    test "usage_summary raises ParseError on a body that is not a JSON object" do
      stub_request(:get, Api::USAGE_SUMMARY_URL).to_return(status: 200, body: "not json")
      assert_raises(Api::ParseError) { Api.usage_summary(access_token: "tok") }

      stub_request(:get, Api::USAGE_SUMMARY_URL).to_return(status: 200, body: "[]")
      assert_raises(Api::ParseError) { Api.usage_summary(access_token: "tok") }
    end

    private

    # Minimal unsigned JWT carrying a `sub` claim (the signature segment is
    # irrelevant — the transport reads the payload without verifying).
    def jwt_with_sub(sub)
      header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
      payload = Base64.urlsafe_encode64({ sub: sub }.to_json, padding: false)
      "#{header}.#{payload}.sig"
    end
  end
end
