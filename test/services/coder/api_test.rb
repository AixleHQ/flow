# frozen_string_literal: true

require "test_helper"

module Coder
  class ApiTest < ActiveSupport::TestCase
    BASE  = "https://coder.example.com"
    TOKEN = "tok-abc"

    test "verify_token returns a hash on 200" do
      stub_request(:get, "#{BASE}/api/v2/users/me")
        .with(headers: { "Coder-Session-Token" => TOKEN })
        .to_return(
          status: 200,
          body: { id: "u1", username: "alice", email: "alice@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      assert_equal "u1", info[:id]
      assert_equal "alice", info[:username]
    end

    test "verify_token raises HTTPError on non-200" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_return(status: 401)
      err = assert_raises(Coder::Api::HTTPError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
      assert_equal 401, err.status
    end

    test "list_workspaces returns the workspaces array" do
      stub_request(:get, "#{BASE}/api/v2/workspaces").to_return(
        status: 200,
        body: { workspaces: [ { id: "u1", name: "n1" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = Coder::Api.list_workspaces(coder_url: BASE, session_token: TOKEN)
      assert_equal 1, result.size
      assert_equal "n1", result.first["name"]
    end

    test "build_workspace accepts 200 and 201" do
      stub_request(:post, "#{BASE}/api/v2/workspaces/ws-1/builds").to_return(
        status: 201,
        body: { id: "build-1" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      build = Coder::Api.build_workspace(
        coder_url: BASE, session_token: TOKEN,
        workspace_id: "ws-1", transition: "start"
      )
      assert_equal "build-1", build["id"]
    end

    test "list_templates returns [] on non-200 without raising" do
      stub_request(:get, "#{BASE}/api/v2/templates").to_return(status: 500)
      assert_equal [], Coder::Api.list_templates(coder_url: BASE, session_token: TOKEN)
    end

    test "ParseError raised on invalid JSON" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_return(
        status: 200, body: "not json",
        headers: { "Content-Type" => "application/json" }
      )

      assert_raises(Coder::Api::ParseError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
    end

    test "TimeoutError raised on Faraday timeout" do
      stub_request(:get, "#{BASE}/api/v2/users/me").to_timeout
      assert_raises(Coder::Api::TimeoutError) do
        Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
      end
    end
  end
end
