# frozen_string_literal: true

require "test_helper"

module Slack
  class ClientTest < ActiveSupport::TestCase
    test "exchange_code returns the parsed body when Slack responds ok" do
      stub_request(:post, "https://slack.com/api/oauth.v2.access")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { ok: true, access_token: "xoxb-1", bot_user_id: "U1", team: { id: "T1", name: "Acme" } }.to_json
        )

      res = Slack::Client.exchange_code(code: "c", redirect_uri: "https://x/cb")

      assert_equal "xoxb-1", res["access_token"]
      assert_equal "T1", res.dig("team", "id")
    end

    test "exchange_code raises Slack::Client::Error when Slack responds ok:false" do
      stub_request(:post, "https://slack.com/api/oauth.v2.access")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { ok: false, error: "invalid_code" }.to_json)

      error = assert_raises(Slack::Client::Error) do
        Slack::Client.exchange_code(code: "c", redirect_uri: "https://x/cb")
      end
      assert_match(/invalid_code/, error.message)
    end

    test "download_file returns the file body with the bearer token" do
      stub_request(:get, "https://files.slack.com/ok")
        .with(headers: { "Authorization" => "Bearer xoxb-1" })
        .to_return(status: 200, body: "hello")

      assert_equal "hello", Slack::Client.download_file(url: "https://files.slack.com/ok", token: "xoxb-1")
    end

    test "download_file aborts when the body exceeds max_bytes" do
      stub_request(:get, "https://files.slack.com/big").to_return(status: 200, body: "x" * 100)

      assert_raises(Slack::Client::Error) do
        Slack::Client.download_file(url: "https://files.slack.com/big", token: "xoxb-1", max_bytes: 10)
      end
    end

    test "auth_test sends the bearer token and parses the result" do
      stub_request(:post, "https://slack.com/api/auth.test")
        .with(headers: { "Authorization" => "Bearer xoxb-1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { ok: true, team_id: "T1", user_id: "U1" }.to_json)

      res = Slack::Client.auth_test(token: "xoxb-1")
      assert_equal "T1", res["team_id"]
    end
  end
end
