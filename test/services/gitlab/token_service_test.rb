# frozen_string_literal: true

require "test_helper"

module Gitlab
  # Contract test: pins Gitlab::TokenService against the real GitLab REST API via
  # WebMock stub_request with realistic payloads (testing doctrine R2/R4). No
  # ::Gitlab / Gitlab::Client constant is stubbed — the gitlab gem runs for real
  # against a stubbed HTTP boundary, so a vendor API change is caught here.
  class TokenServiceTest < ActiveSupport::TestCase
    GITLAB_API = "https://gitlab.com/api/v4"

    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
      @token = @integration.credentials_data["personal_access_token"]

      Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: GITLAB_API))
    end

    test "verify_token returns parsed user info from GET /user" do
      stub_request(:get, "#{GITLAB_API}/user")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            id: 152, username: "alice", name: "Alice Smith", email: "alice@example.com",
            state: "active", web_url: "https://gitlab.com/alice",
            avatar_url: "https://gitlab.com/uploads/-/system/user/avatar/152/avatar.png",
            created_at: "2021-03-14T09:00:00.000Z", is_admin: false, can_create_project: true
          }.to_json
        )

      info = Gitlab::TokenService.new(@integration).verify_token

      assert_equal 152, info[:id]
      assert_equal "alice", info[:username]
      assert_equal "Alice Smith", info[:name]
      assert_equal "alice@example.com", info[:email]
    end

    test "client targets the configured endpoint with the PRIVATE-TOKEN header" do
      stub_request(:get, "#{GITLAB_API}/user")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: 1, username: "u", name: "U", email: "u@example.com" }.to_json)

      Gitlab::TokenService.new(@integration).verify_token

      assert_requested :get, "#{GITLAB_API}/user", headers: { "PRIVATE-TOKEN" => @token }
    end

    test "raises ConfigurationError when personal_access_token is blank" do
      @integration.credentials_data = {}
      @integration.save!

      service = Gitlab::TokenService.new(@integration)
      assert_raises(Gitlab::TokenService::ConfigurationError) { service.client }
    end

    test "raises AuthenticationError on 401 Unauthorized" do
      stub_request(:get, "#{GITLAB_API}/user")
        .to_return(status: 401, headers: { "Content-Type" => "application/json" },
          body: { message: "401 Unauthorized" }.to_json)

      error = assert_raises(Gitlab::TokenService::AuthenticationError) do
        Gitlab::TokenService.new(@integration).verify_token
      end
      assert_match(/GitLab token verification failed/, error.message)
    end

    test "raises AuthenticationError on 403 Forbidden" do
      stub_request(:get, "#{GITLAB_API}/user")
        .to_return(status: 403, headers: { "Content-Type" => "application/json" },
          body: { message: "403 Forbidden" }.to_json)

      assert_raises(Gitlab::TokenService::AuthenticationError) do
        Gitlab::TokenService.new(@integration).verify_token
      end
    end
  end
end
