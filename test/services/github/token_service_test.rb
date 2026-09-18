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

      # Worker-unique path: the suite runs parallel (one forked worker per core),
      # so a fixed tmp filename would let one worker's teardown delete the pem
      # another worker is mid-read on. Process.pid is stable within a worker.
      @pem_path = Rails.root.join("tmp", "test-github-app-#{Process.pid}.pem")
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

    # ----- PAT mode -----
    #
    # A personal access token is the credential, not the seed of one: nothing is
    # minted, so no App id and no installation are needed — which is the whole
    # point of the mode.

    test "generate_installation_token hands back the stored token in PAT mode" do
      service = Github::TokenService.new(pat_integration("ghp_developer_token"))

      assert service.pat_mode?
      assert_equal "ghp_developer_token", service.generate_installation_token
    end

    test "PAT mode ignores the repositories argument rather than narrowing the token" do
      service = Github::TokenService.new(pat_integration("ghp_developer_token"))

      assert_equal "ghp_developer_token", service.generate_installation_token(repositories: %w[my-repo])
    end

    test "PAT mode needs neither an App id nor an installation id" do
      Settings.github.stubs(:app_id).returns(nil)
      integration = pat_integration("ghp_developer_token")

      assert_equal "ghp_developer_token", Github::TokenService.new(integration).generate_installation_token
    end

    test "verify_token returns the token's identity and classic scopes" do
      stub_request(:get, "https://api.github.com/user")
        .with(headers: { "Authorization" => "token ghp_developer_token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "repo, workflow" },
          body: { id: 4_242, login: "octodev", type: "User" }.to_json
        )

      info = Github::TokenService.new(pat_integration("ghp_developer_token")).verify_token

      assert_equal 4_242, info[:id]
      assert_equal "octodev", info[:account_login]
      assert_equal "User", info[:account_type]
      assert_equal %w[repo workflow], info[:scopes]
    end

    # A fine-grained token's permissions are per repository and GitHub reports
    # none of them on this endpoint. nil says "not reported" — distinct from the
    # empty list a scopeless classic token comes back with.
    test "verify_token reports nil scopes for a fine-grained token" do
      stub_request(:get, "https://api.github.com/user")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { id: 7, login: "octodev", type: "User" }.to_json
        )

      info = Github::TokenService.new(pat_integration("github_pat_x")).verify_token

      assert_nil info[:scopes]
      assert_equal "octodev", info[:account_login]
    end

    test "verify_token refuses a classic token with no repository scope" do
      stub_request(:get, "https://api.github.com/user")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "gist" },
          body: { id: 7, login: "octodev", type: "User" }.to_json
        )

      error = assert_raises(Github::TokenService::AuthenticationError) do
        Github::TokenService.new(pat_integration("ghp_gist_only")).verify_token
      end
      assert_match(/no repository access/, error.message)
    end

    test "verify_token accepts a classic token scoped to public repositories only" do
      stub_request(:get, "https://api.github.com/user")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json", "X-OAuth-Scopes" => "public_repo" },
          body: { id: 7, login: "octodev", type: "User" }.to_json
        )

      info = Github::TokenService.new(pat_integration("ghp_public_only")).verify_token

      assert_equal %w[public_repo], info[:scopes]
    end

    test "verify_token raises AuthenticationError when GitHub rejects the token" do
      stub_request(:get, "https://api.github.com/user")
        .to_return(
          status: 401,
          headers: { "Content-Type" => "application/json" },
          body: { message: "Bad credentials" }.to_json
        )

      error = assert_raises(Github::TokenService::AuthenticationError) do
        Github::TokenService.new(pat_integration("ghp_revoked")).verify_token
      end
      assert_match(/invalid, revoked or expired/, error.message)
    end

    test "raises ConfigurationError when a PAT integration carries no token" do
      integration = build(:integration, :github, company: @company, connected_by: @user)
      integration.credentials_data = {}
      integration.settings = { "auth_mode" => "pat" }
      integration.save!

      assert_raises(Github::TokenService::ConfigurationError) do
        Github::TokenService.new(integration)
      end
    end

    private

    def pat_integration(token)
      integration = build(:integration, :github_pat, :active, company: @company, connected_by: @user)
      integration.credentials_data = { personal_access_token: token }
      integration.save!
      integration
    end

    def generate_test_pem(path)
      key = OpenSSL::PKey::RSA.generate(2048)
      File.write(path, key.to_pem)
    end
  end
end
