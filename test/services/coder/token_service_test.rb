# frozen_string_literal: true

require "test_helper"

module Coder
  class TokenServiceTest < ActiveSupport::TestCase
    setup do
      resolve_hosts_publicly!
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = build(:integration, :coder, :active, company: @company, connected_by: @user)
      @integration.credentials_data = {
        coder_url: "https://coder.example.com",
        session_token: "test-token-xyz"
      }
      @integration.save!
    end

    test "verify_token returns user info on 200" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .with(headers: { "Coder-Session-Token" => "test-token-xyz" })
        .to_return(
          status: 200,
          body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::TokenService.new(@integration).verify_token

      assert_equal "user-uuid", info[:id]
      assert_equal "alice", info[:username]
      assert_equal "alice@example.com", info[:email]
    end

    test "raises AuthenticationError on 401" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(status: 401)

      assert_raises(Coder::TokenService::AuthenticationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "raises AuthenticationError on 403" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(status: 403)

      assert_raises(Coder::TokenService::AuthenticationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "raises AuthenticationError on timeout" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me").to_timeout

      assert_raises(Coder::TokenService::AuthenticationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "raises AuthenticationError on invalid JSON" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
        status: 200,
        body: "not json",
        headers: { "Content-Type" => "application/json" }
      )

      assert_raises(Coder::TokenService::AuthenticationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "raises ConfigurationError when coder_url is missing" do
      @integration.credentials_data = { session_token: "tok" }
      @integration.save!

      assert_raises(Coder::TokenService::ConfigurationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "raises ConfigurationError when session_token is missing" do
      @integration.credentials_data = { coder_url: "https://coder.example.com" }
      @integration.save!

      assert_raises(Coder::TokenService::ConfigurationError) do
        Coder::TokenService.new(@integration).verify_token
      end
    end

    test "AuthenticationError messages never contain the raw session token" do
      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .to_raise(Faraday::ConnectionFailed.new("connection failed test-token-xyz"))

      begin
        Coder::TokenService.new(@integration).verify_token
        flunk "Expected AuthenticationError"
      rescue Coder::TokenService::AuthenticationError => e
        refute_includes e.message, "test-token-xyz"
      end
    end

    # ==================================================================
    # Outbound DNS path selection by trusted-host check
    #
    # Trusted host      → resolved normally via internal DNS.
    # Non-trusted host  → must not use internal DNS: dialed at its public IPv4
    #                     from public DNS, or not at all.
    # ==================================================================

    test "a non-trusted host is dialed at its public IPv4 under its own name" do
      UrlSafetyValidator.stubs(:configured_trusted_hosts).returns([])
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.example.com").returns("93.184.215.14")

      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .with(headers: { "Coder-Session-Token" => "test-token-xyz" })
        .to_return(
          status: 200,
          body: { id: "u1", username: "stager", email: "s@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      assert_equal "93.184.215.14", Coder::Api.dial_address(URI("https://coder.example.com"))
      assert_equal "stager", Coder::TokenService.new(@integration).verify_token[:username]
    end

    test "trusted host resolves through internal DNS, not public DNS" do
      @integration.credentials_data = {
        coder_url: "https://coder.staging.aixle.com",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:configured_trusted_hosts).returns([ "coder.staging.aixle.com" ])
      UrlSafetyValidator.expects(:resolve_public_ipv4).never

      stub_request(:get, "https://coder.staging.aixle.com/api/v2/users/me")
        .to_return(
          status: 200,
          body: { id: "u2", username: "alice", email: "a@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      assert_nil Coder::Api.dial_address(URI("https://coder.staging.aixle.com"))
      assert_equal "alice", Coder::TokenService.new(@integration).verify_token[:username]
    end

    # With no public address the system resolver is the only one left, and its
    # answer can be an internal address the URL did not have when it was saved.
    test "a non-trusted host with no public address is refused, not resolved internally" do
      UrlSafetyValidator.stubs(:configured_trusted_hosts).returns([])
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.example.com").returns(nil)
      UrlSafetyValidator.stubs(:resolved_addresses).with("coder.example.com").returns([ IPAddr.new("10.0.0.5") ])
      internal = stub_request(:get, "https://coder.example.com/api/v2/users/me")

      assert_raises(Coder::Api::UnsafeUrlError) do
        Coder::Api.verify_token(coder_url: "https://coder.example.com", session_token: "test-token-xyz")
      end
      assert_raises(Coder::TokenService::AuthenticationError) { Coder::TokenService.new(@integration).verify_token }
      assert_not_requested internal
    end

    test "a literal internal address is refused" do
      UrlSafetyValidator.stubs(:configured_trusted_hosts).returns([])

      %w[https://10.0.0.5 https://0.0.0.0 https://100.64.0.7 https://169.254.169.254 https://localhost].each do |url|
        assert_raises(Coder::Api::UnsafeUrlError, url) { Coder::Api.dial_address(URI(url)) }
      end
    end

    test "non-trusted host on a non-default port keeps its port" do
      @integration.credentials_data = {
        coder_url: "https://coder.example.com:8443",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:configured_trusted_hosts).returns([])
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.example.com").returns("93.184.215.14")

      stub_request(:get, "https://coder.example.com:8443/api/v2/users/me")
        .to_return(
          status: 200,
          body: { id: "u4", username: "portuser", email: "p@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::TokenService.new(@integration).verify_token
      assert_equal "portuser", info[:username]
    end
  end
end
