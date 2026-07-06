# frozen_string_literal: true

require "test_helper"

module Github
  # Contract tests (testing doctrine R4): the adapter is pinned to the real
  # api.github.com surface with WebMock stub_request + realistic payloads — no
  # Octokit constant is mocked, so this file stays out of the
  # Testing/NoVendorStubbing Exclude.
  class TokenServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = build(:integration, :github, :active, company: @company, connected_by: @user)
      @integration.credentials_data = { "installation_id" => "12345" }
      @integration.save!

      @pem_path = Rails.root.join("tmp", "test-github-app.pem")
      generate_test_pem(@pem_path)

      # Stub, don't assign: assigning mutates the process-global Settings and
      # leaks a path to a deleted pem into every later test in this process.
      Settings.github.stubs(:app_id).returns("999")
      Settings.github.stubs(:private_key_path).returns(@pem_path.to_s)
    end

    teardown do
      File.delete(@pem_path) if File.exist?(@pem_path)
    end

    test "generate_installation_token returns the token from the access-tokens endpoint" do
      stub_request(:post, "https://api.github.com/app/installations/12345/access_tokens")
        .to_return(
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: {
            token: "ghs_test_token_abc123",
            expires_at: "2026-07-05T12:00:00Z",
            permissions: { contents: "read", pull_requests: "write" },
            repository_selection: "all"
          }.to_json
        )

      token = Github::TokenService.new(@integration).generate_installation_token

      assert_equal "ghs_test_token_abc123", token
    end

    test "generate_installation_token scopes the request body to specific repositories" do
      scoped = stub_request(:post, "https://api.github.com/app/installations/12345/access_tokens")
        .with(body: hash_including("repositories" => %w[my-repo]))
        .to_return(
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { token: "ghs_scoped_token", repository_selection: "selected" }.to_json
        )

      token = Github::TokenService.new(@integration).generate_installation_token(repositories: %w[my-repo])

      assert_equal "ghs_scoped_token", token
      assert_requested scoped
    end

    test "verify_installation returns the parsed installation info" do
      stub_request(:get, "https://api.github.com/app/installations/12345")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            id: 12_345,
            account: { login: "acme-corp", type: "Organization" },
            target_type: "Organization",
            permissions: { contents: "read", pull_requests: "write" }
          }.to_json
        )

      info = Github::TokenService.new(@integration).verify_installation

      assert_equal 12_345, info[:id]
      assert_equal "acme-corp", info[:account_login]
      assert_equal "Organization", info[:account_type]
      assert_equal "Organization", info[:target_type]
      assert_equal({ contents: "read", pull_requests: "write" }, info[:permissions])
    end

    test "raises ConfigurationError when app_id is blank" do
      Settings.github.stubs(:app_id).returns(nil)

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

    test "raises AuthenticationError when GitHub rejects the token request" do
      stub_request(:post, "https://api.github.com/app/installations/12345/access_tokens")
        .to_return(
          status: 401,
          headers: { "Content-Type" => "application/json" },
          body: { message: "Bad credentials", documentation_url: "https://docs.github.com/rest" }.to_json
        )

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
