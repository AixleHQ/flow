# frozen_string_literal: true

require "test_helper"

module Coder
  class TokenServiceTest < ActiveSupport::TestCase
    setup do
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
    # Trusted-host outbound DNS fallback
    # ==================================================================

    test "for a trusted host the request is routed to the public IPv4" do
      @integration.credentials_data = {
        coder_url: "https://coder.staging.aixle.com",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:trusted_host?).with("coder.staging.aixle.com").returns(true)
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.staging.aixle.com").returns("203.0.113.10")

      stub_request(:get, "https://203.0.113.10/api/v2/users/me")
        .with(headers: {
          "Coder-Session-Token" => "test-token-xyz",
          "Host" => "coder.staging.aixle.com"
        })
        .to_return(
          status: 200,
          body: { id: "u1", username: "stager", email: "s@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::TokenService.new(@integration).verify_token

      assert_equal "stager", info[:username]
    end

    test "non-trusted host is not rewritten to a public IPv4" do
      @integration.credentials_data = {
        coder_url: "https://coder.example.com",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:trusted_host?).with("coder.example.com").returns(false)
      UrlSafetyValidator.expects(:resolve_public_ipv4).never

      stub_request(:get, "https://coder.example.com/api/v2/users/me")
        .to_return(
          status: 200,
          body: { id: "u2", username: "alice", email: "a@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::TokenService.new(@integration).verify_token
      assert_equal "alice", info[:username]
    end

    test "trusted host falls back to original URL when public DNS yields nothing" do
      @integration.credentials_data = {
        coder_url: "https://coder.staging.aixle.com",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:trusted_host?).with("coder.staging.aixle.com").returns(true)
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.staging.aixle.com").returns(nil)

      stub_request(:get, "https://coder.staging.aixle.com/api/v2/users/me")
        .to_return(
          status: 200,
          body: { id: "u3", username: "fallback", email: "f@example.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      info = Coder::TokenService.new(@integration).verify_token
      assert_equal "fallback", info[:username]
    end

    test "trusted host on a non-default port preserves port in Host header" do
      @integration.credentials_data = {
        coder_url: "https://coder.staging.aixle.com:8443",
        session_token: "test-token-xyz"
      }
      @integration.save!

      UrlSafetyValidator.stubs(:trusted_host?).with("coder.staging.aixle.com").returns(true)
      UrlSafetyValidator.stubs(:resolve_public_ipv4).with("coder.staging.aixle.com").returns("203.0.113.10")

      stub_request(:get, "https://203.0.113.10:8443/api/v2/users/me")
        .with(headers: { "Host" => "coder.staging.aixle.com:8443" })
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
