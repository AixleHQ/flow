# frozen_string_literal: true

require "test_helper"

module Github
  class TokenServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = build(:integration, :github, :active, company: @company, connected_by: @user)
      @integration.credentials_data = { "installation_id" => "12345" }
      @integration.save!

      @pem_path = Rails.root.join("tmp", "test-github-app.pem")
      generate_test_pem(@pem_path)

      Settings.github.app_id = "999"
      Settings.github.private_key_path = @pem_path.to_s
    end

    teardown do
      File.delete(@pem_path) if File.exist?(@pem_path)
    end

    test "generate_installation_token returns token string" do
      mock_client = mock("octokit_client")
      token_response = OpenStruct.new(token: "ghs_test_token_abc123")
      mock_client.expects(:create_app_installation_access_token).with(12_345).returns(token_response)

      Octokit::Client.expects(:new).returns(mock_client)

      service = Github::TokenService.new(@integration)
      token = service.generate_installation_token
      assert_equal "ghs_test_token_abc123", token
    end

    test "verify_installation returns installation info" do
      mock_client = mock("octokit_client")
      installation = OpenStruct.new(
        id: 12_345,
        account: OpenStruct.new(login: "acme-corp", type: "Organization"),
        target_type: "Organization",
        permissions: { contents: "read", pull_requests: "write" }
      )
      mock_client.expects(:installation).with(12_345).returns(installation)

      Octokit::Client.expects(:new).returns(mock_client)

      service = Github::TokenService.new(@integration)
      info = service.verify_installation

      assert_equal 12_345, info[:id]
      assert_equal "acme-corp", info[:account_login]
      assert_equal "Organization", info[:account_type]
    end

    test "raises ConfigurationError when app_id is blank" do
      Settings.github.app_id = nil

      assert_raises(Github::TokenService::ConfigurationError) do
        Github::TokenService.new(@integration)
      end
    end

    test "raises ConfigurationError when integration has no installation_id" do
      @integration.credentials_data = {}
      @integration.save!

      assert_raises(Github::TokenService::ConfigurationError) do
        Github::TokenService.new(@integration)
      end
    end

    test "raises AuthenticationError on Octokit failure" do
      mock_client = mock("octokit_client")
      mock_client.expects(:create_app_installation_access_token).raises(Octokit::Unauthorized.new(method: :post, status: 401))

      Octokit::Client.expects(:new).returns(mock_client)

      service = Github::TokenService.new(@integration)
      assert_raises(Github::TokenService::AuthenticationError) do
        service.generate_installation_token
      end
    end

    private

    def generate_test_pem(path)
      key = OpenSSL::PKey::RSA.generate(2048)
      File.write(path, key.to_pem)
    end
  end
end
