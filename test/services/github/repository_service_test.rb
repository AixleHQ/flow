# frozen_string_literal: true

require "test_helper"

module Github
  # Contract tests (testing doctrine R4): the adapter is pinned to the real
  # api.github.com surface with WebMock stub_request + realistic payloads. The
  # collaborating Github::TokenService is real (R5, sociable) — its installation
  # token endpoint is stubbed alongside the repository endpoints rather than
  # mocking the class. No Octokit constant is mocked, so this file stays out of
  # the Testing/NoVendorStubbing Exclude.
  class RepositoryServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
      @integration.credentials_data = { "installation_id" => "12345" }
      @integration.save!

      # The real TokenService signs a JWT from a GitHub App id + private key.
      @pem_path = Rails.root.join("tmp", "test-github-repo-svc.pem")
      generate_test_pem(@pem_path)
      Settings.github.stubs(:app_id).returns("999")
      Settings.github.stubs(:private_key_path).returns(@pem_path.to_s)

      stub_installation_token("ghs_repo_svc_token")
    end

    teardown do
      File.delete(@pem_path) if File.exist?(@pem_path)
    end

    test "list_available returns the parsed repositories from the installation endpoint" do
      stub_request(:get, "https://api.github.com/installation/repositories")
        .with(query: { per_page: 100 })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            total_count: 2,
            repositories: [
              { full_name: "org/app", default_branch: "main",
                clone_url: "https://github.com/org/app.git", private: false, description: "Main app" },
              { full_name: "org/lib", default_branch: "develop",
                clone_url: "https://github.com/org/lib.git", private: true, description: nil }
            ]
          }.to_json
        )

      result = Github::RepositoryService.new(@integration).list_available

      assert_equal 2, result.length
      assert_equal "org/app", result[0][:full_name]
      assert_equal "main", result[0][:default_branch]
      assert_equal "https://github.com/org/app.git", result[0][:clone_url]
      assert_equal false, result[0][:is_private] # rubocop:disable Minitest/RefuteFalse
      assert_equal "org/lib", result[1][:full_name]
      assert result[1][:is_private]
      assert_nil result[1][:description]
    end

    test "list_available returns an empty array when the API errors" do
      stub_request(:get, "https://api.github.com/installation/repositories")
        .with(query: { per_page: 100 })
        .to_return(
          status: 401,
          headers: { "Content-Type" => "application/json" },
          body: { message: "Bad credentials" }.to_json
        )

      assert_equal [], Github::RepositoryService.new(@integration).list_available
    end

    test "find_repo returns the parsed repo info" do
      stub_request(:get, "https://api.github.com/repos/org/app")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            full_name: "org/app", default_branch: "main",
            clone_url: "https://github.com/org/app.git", private: false, description: "Main app"
          }.to_json
        )

      result = Github::RepositoryService.new(@integration).find_repo("org/app")

      assert_equal "org/app", result[:full_name]
      assert_equal "main", result[:default_branch]
      assert_equal "https://github.com/org/app.git", result[:clone_url]
      assert_equal false, result[:is_private] # rubocop:disable Minitest/RefuteFalse
    end

    test "find_repo returns nil when the repo is not found" do
      stub_request(:get, "https://api.github.com/repos/org/nonexistent")
        .to_return(
          status: 404,
          headers: { "Content-Type" => "application/json" },
          body: { message: "Not Found" }.to_json
        )

      assert_nil Github::RepositoryService.new(@integration).find_repo("org/nonexistent")
    end

    test "list_branches returns the branch names" do
      stub_request(:get, "https://api.github.com/repos/org/app/branches")
        .with(query: { per_page: 100 })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [
            { name: "main", protected: true },
            { name: "develop", protected: false }
          ].to_json
        )

      assert_equal %w[main develop], Github::RepositoryService.new(@integration).list_branches("org/app")
    end

    private

    def stub_installation_token(token)
      stub_request(:post, "https://api.github.com/app/installations/12345/access_tokens")
        .to_return(
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { token: token, repository_selection: "all" }.to_json
        )
    end

    def generate_test_pem(path)
      key = OpenSSL::PKey::RSA.generate(2048)
      File.write(path, key.to_pem)
    end
  end
end
