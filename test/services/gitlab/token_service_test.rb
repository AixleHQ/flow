# frozen_string_literal: true

require "test_helper"

module Gitlab
  class TokenServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)

      Settings.stubs(:gitlab).returns(
        OpenStruct.new(endpoint: "https://gitlab.com/api/v4")
      )
    end

    test "verify_token returns user info" do
      mock_client = mock("gitlab_client")
      user = OpenStruct.new(id: 1, username: "alice", name: "Alice Smith", email: "alice@example.com")
      mock_client.expects(:user).returns(user)

      ::Gitlab.expects(:client).returns(mock_client)

      service = Gitlab::TokenService.new(@integration)
      info = service.verify_token

      assert_equal 1, info[:id]
      assert_equal "alice", info[:username]
      assert_equal "Alice Smith", info[:name]
      assert_equal "alice@example.com", info[:email]
    end

    test "raises ConfigurationError when personal_access_token is blank" do
      @integration.credentials_data = {}
      @integration.save!

      service = Gitlab::TokenService.new(@integration)
      assert_raises(Gitlab::TokenService::ConfigurationError) do
        service.client
      end
    end

    test "raises AuthenticationError on Unauthorized response" do
      mock_client = mock("gitlab_client")
      mock_client.expects(:user).raises(::Gitlab::Error::Unauthorized.new("401 Unauthorized"))

      ::Gitlab.expects(:client).returns(mock_client)

      service = Gitlab::TokenService.new(@integration)
      assert_raises(Gitlab::TokenService::AuthenticationError) do
        service.verify_token
      end
    end

    test "client uses configured endpoint" do
      ::Gitlab.expects(:client).with(
        endpoint: "https://gitlab.com/api/v4",
        private_token: anything
      ).returns(mock("client"))

      service = Gitlab::TokenService.new(@integration)
      service.client
    end
  end
end
