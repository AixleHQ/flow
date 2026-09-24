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
      # Worker-unique path (parallel suite): a fixed tmp filename races across
      # forked workers — one worker's teardown deletes the pem another is reading.
      @pem_path = Rails.root.join("tmp", "test-github-repo-svc-#{Process.pid}.pem")
      generate_test_pem(@pem_path)
      Settings.github.stubs(:app_id).returns("999")
      Settings.github.stubs(:private_key_path).returns(@pem_path.to_s)

      stub_installation_token("ghs_repo_svc_token")
    end

    teardown do
      FileUtils.rm_f(@pem_path)
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

    test "list_branches follows the pages, and stops at the cap" do
      cap = Github::RepositoryService::MAX_PAGES
      (1..(cap + 1)).each do |page|
        query = page == 1 ? { per_page: 100 } : { per_page: 100, page: page }
        link = %(<https://api.github.com/repos/org/app/branches?per_page=100&page=#{page + 1}>; rel="next")
        stub_request(:get, "https://api.github.com/repos/org/app/branches")
          .with(query: query)
          .to_return(status: 200, headers: { "Content-Type" => "application/json", "Link" => link },
                     body: [ { name: "branch-#{page}" } ].to_json)
      end

      branches = Github::RepositoryService.new(@integration).list_branches("org/app")

      assert_equal (1..cap).map { |page| "branch-#{page}" }, branches
      assert_not_requested :get, "https://api.github.com/repos/org/app/branches?per_page=100&page=#{cap + 1}"
    end

    # ----- PAT mode -----
    #
    # A personal access token cannot read /installation/repositories — GitHub
    # answers 403 "Resource not accessible by personal access token" — so the
    # adapter has to ask what the token's owner can reach instead.

    test "list_available reads the user's own repositories in PAT mode" do
      pat = stub_request(:get, "https://api.github.com/user/repos")
        .with(query: { affiliation: "owner,collaborator,organization_member", per_page: 100 },
              headers: { "Authorization" => "token ghp_developer_token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [
            { full_name: "octodev/side-project", default_branch: "main",
              clone_url: "https://github.com/octodev/side-project.git", private: true, description: "Mine" },
            { full_name: "someorg/service", default_branch: "trunk",
              clone_url: "https://github.com/someorg/service.git", private: true, description: nil }
          ].to_json
        )

      result = Github::RepositoryService.new(pat_integration).list_available

      assert_requested pat
      assert_equal %w[octodev/side-project someorg/service], result.map { |r| r[:full_name] }
      assert_equal "trunk", result[1][:default_branch]
      assert result[0][:is_private]
    end

    test "list_branches authenticates with the stored token in PAT mode" do
      stub_request(:get, "https://api.github.com/repos/someorg/service/branches")
        .with(query: { per_page: 100 }, headers: { "Authorization" => "token ghp_developer_token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [ { name: "main" }, { name: "trunk" } ].to_json
        )

      assert_equal %w[main trunk], Github::RepositoryService.new(pat_integration).list_branches("someorg/service")
    end

    private

    # Deliberately built with no App settings in play: the PAT path must not
    # touch the installation-token endpoint, and a request to it would fail the
    # WebMock fence rather than pass silently.
    def pat_integration
      integration = build(:integration, :github_pat, :active, company: @company, connected_by: @user)
      integration.credentials_data = { personal_access_token: "ghp_developer_token" }
      integration.save!
      integration
    end

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
