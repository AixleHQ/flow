# frozen_string_literal: true

require "test_helper"

# The transport a customer-chosen YouTrack URL goes through: https only, the
# vetted address pinned, no redirects followed, bounded answers.
class Youtrack::ClientTest < ActiveSupport::TestCase
  BASE = "https://yt.example.com/youtrack"

  setup do
    resolve_hosts_publicly!
    @client = Youtrack::Client.new(base_url: BASE, token: "perm:abc", retry_delay: 0)
  end

  test "a request carries the bearer token and answers parsed JSON" do
    stub = stub_request(:get, "#{BASE}/api/users/me?fields=id,login")
           .with(headers: { "Authorization" => "Bearer perm:abc", "Accept" => "application/json" })
           .to_return(status: 200, body: { id: "1-1", login: "aixle" }.to_json)

    assert_equal({ "id" => "1-1", "login" => "aixle" }, @client.get("/api/users/me", fields: "id,login"))
    assert_requested stub
  end

  test "http, private hosts and redirects are refused" do
    assert_match(/https/, assert_raises(Trackers::Error) { Youtrack::Client.new(base_url: "http://yt.example.com", token: "t").get("/api/x") }.message)

    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("10.0.0.7") ])
    assert_match(/private/, assert_raises(Trackers::Error) { @client.get("/api/x") }.message)

    resolve_hosts_publicly!
    stub_request(:get, "#{BASE}/api/x").to_return(status: 302, headers: { "Location" => "https://evil.example/" })
    assert_match(/redirected/, assert_raises(Trackers::Error) { @client.get("/api/x") }.message)
  end

  test "an operator-trusted host on a private network is reached" do
    Settings.stubs(:youtrack).returns(Hashie::Mash.new(trusted_hosts: "yt.example.com, other.internal"))
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("10.0.0.7") ])
    stub_request(:get, "#{BASE}/api/x").to_return(status: 200, body: "{}")

    assert_equal({}, @client.get("/api/x"))
  end

  test "YouTrack's failures become stable codes" do
    { 401 => "not_authorized", 403 => "permission_denied", 404 => "not_found", 429 => "rate_limited", 400 => "validation_failed" }.each do |status, code|
      stub_request(:get, "#{BASE}/api/x").to_return(status: status, body: { error: "bad", error_description: "Nope" }.to_json)
      assert_equal code, assert_raises(Trackers::Error) { @client.get("/api/x") }.code, status
    end
    stub_request(:post, "#{BASE}/api/y").to_return(status: 400, body: { error_description: "State is required" }.to_json)
    assert_equal "State is required", assert_raises(Trackers::Error) { @client.post("/api/y", {}) }.message
  end

  test "a read is retried on a gateway error; a write that failed on the server is outcome unknown" do
    stub_request(:get, "#{BASE}/api/x").to_return({ status: 503 }, { status: 200, body: "[]" })
    stub_request(:post, "#{BASE}/api/y").to_return(status: 503)
    stub_request(:post, "#{BASE}/api/z").to_raise(Net::ReadTimeout)

    assert_equal [], @client.get("/api/x")
    assert_raises(Trackers::Error::OutcomeUnknown) { @client.post("/api/y", { text: "x" }) }
    assert_raises(Trackers::Error::OutcomeUnknown) { @client.post("/api/z", { text: "x" }) }
  end

  test "an answer larger than the bound is refused, and one that is not JSON names the likely cause" do
    stub_request(:get, "#{BASE}/api/big").to_return(status: 200, body: "x" * (Youtrack::Client::MAX_BYTES + 1))
    stub_request(:get, "#{BASE}/api/html").to_return(status: 200, body: "<html>login</html>")

    assert_match(/too large/, assert_raises(Trackers::Error) { @client.get("/api/big") }.message)
    assert_match(/instance's URL/, assert_raises(Trackers::Error) { @client.get("/api/html") }.message)
  end
end
