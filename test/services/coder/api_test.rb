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

    # ==================================================================
    # SNI-preserving trusted-host TCP override
    # ==================================================================

    test "SniPreservingNetHttp points TCP at ipaddr while keeping the hostname address" do
      adapter = Coder::Api::SniPreservingNetHttp.new(nil, { ipaddr: "203.0.113.10" })
      env = Faraday::Env.from(
        url: URI("https://coder.staging.aixle.com/api/v2/users/me"),
        request: Faraday::RequestOptions.new
      )

      http = adapter.net_http_connection(env)

      # The address must stay the hostname — Net::HTTP derives TLS SNI,
      # certificate verification, and the Host header from it; ipaddr only
      # redirects the TCP connection.
      assert_equal "coder.staging.aixle.com", http.address
      assert_equal "203.0.113.10", http.ipaddr
    end

    test "SniPreservingNetHttp without ipaddr behaves like the stock adapter" do
      adapter = Coder::Api::SniPreservingNetHttp.new(nil, {})
      env = Faraday::Env.from(
        url: URI("https://coder.example.com/api"),
        request: Faraday::RequestOptions.new
      )

      http = adapter.net_http_connection(env)

      assert_equal "coder.example.com", http.address
      assert_nil http.ipaddr
    end

    test "override decision trusts the union of global and CODER_TRUSTED_HOSTS lists" do
      coder_hosts = Array(Settings.coder.trusted_hosts).map(&:to_s)
      UrlSafetyValidator
        .expects(:trusted_host?)
        .with("coder.example.com", trusted_hosts_override: coder_hosts)
        .returns(false)

      stub_request(:get, "#{BASE}/api/v2/users/me").to_return(
        status: 200,
        body: { id: "u1", username: "a", email: "a@example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      Coder::Api.verify_token(coder_url: BASE, session_token: TOKEN)
    end
  end
end
