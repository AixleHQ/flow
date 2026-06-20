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
  end
end
