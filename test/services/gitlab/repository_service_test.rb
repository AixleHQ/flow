# frozen_string_literal: true

require "test_helper"

module Gitlab
  # Contract test: pins Gitlab::RepositoryService against the real GitLab REST API
  # via WebMock stub_request with realistic payloads (testing doctrine R2/R4). The
  # real Gitlab::TokenService + gitlab gem run against a stubbed HTTP boundary —
  # no ::Gitlab/Gitlab::Client constant and no internal collaborator is mocked, so
  # this exercises the true request/response translation.
  class RepositoryServiceTest < ActiveSupport::TestCase
    GITLAB_API = "https://gitlab.com/api/v4"
    WEBHOOK_URL = "https://aixle.example.com/webhooks/gitlab"

    # GitLab percent-encodes "group/app" to "group%2Fapp"; tolerate either form
    # in case the HTTP stack normalizes the encoded slash.
    ENCODED_APP = %r{group(?:%2F|/)app}

    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)

      Settings.stubs(:gitlab).returns(OpenStruct.new(endpoint: GITLAB_API))
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("aixle.example.com")
    end

    test "list_available maps GET /projects into the adapter shape" do
      stub_request(:get, "#{GITLAB_API}/projects")
        .with(query: hash_including("membership" => "true", "per_page" => "100"))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: [
            gl_project(path: "group/app", branch: "main", visibility: "private", description: "Main app"),
            gl_project(path: "group/lib", branch: "develop", visibility: "public", description: nil)
          ].to_json)

      result = Gitlab::RepositoryService.new(@integration).list_available

      assert_equal 2, result.length
      assert_equal "group/app", result[0][:full_name]
      assert_equal "main", result[0][:default_branch]
      assert_equal "https://gitlab.com/group/app.git", result[0][:clone_url]
      assert result[0][:is_private]
      assert_equal "group/lib", result[1][:full_name]
      assert_equal false, result[1][:is_private] # rubocop:disable Minitest/RefuteFalse
    end

    test "list_available returns [] when GitLab rejects the token" do
      stub_request(:get, "#{GITLAB_API}/projects")
        .with(query: hash_including("membership" => "true"))
        .to_return(status: 401, headers: { "Content-Type" => "application/json" },
          body: { message: "401 Unauthorized" }.to_json)

      assert_equal [], Gitlab::RepositoryService.new(@integration).list_available
    end

    test "find_repo maps GET /projects/:id into the adapter shape" do
      stub_request(:get, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}(?:\z|\?)})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: gl_project(path: "group/app", branch: "main", visibility: "private", description: "Main app").to_json)

      result = Gitlab::RepositoryService.new(@integration).find_repo("group/app")

      assert_equal "group/app", result[:full_name]
      assert_equal "main", result[:default_branch]
      assert_equal "https://gitlab.com/group/app.git", result[:clone_url]
      assert result[:is_private]
    end

    test "find_repo returns nil when the project is not found" do
      stub_request(:get, %r{\A#{Regexp.escape(GITLAB_API)}/projects/group(?:%2F|/)nonexistent(?:\z|\?)})
        .to_return(status: 404, headers: { "Content-Type" => "application/json" },
          body: { message: "404 Project Not Found" }.to_json)

      assert_nil Gitlab::RepositoryService.new(@integration).find_repo("group/nonexistent")
    end

    test "list_branches maps GET /repository/branches to branch names" do
      stub_request(:get, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/repository/branches})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: [ gl_branch("main"), gl_branch("develop") ].to_json)

      result = Gitlab::RepositoryService.new(@integration).list_branches("group/app")

      assert_equal %w[main develop], result
    end

    test "configure stores a secret and registers a pipeline webhook via POST /hooks" do
      repository = create(:repository, full_name: "group/app", integration: @integration, scope: @project)

      stub_request(:post, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks\z})
        .to_return(status: 201, headers: { "Content-Type" => "application/json" },
          body: gl_hook(id: 7, url: WEBHOOK_URL, pipeline_events: true).to_json)

      Gitlab::RepositoryService.new(@integration).configure(repository)
      repository.reload

      assert_not_nil repository.webhook_secret
      assert_equal 64, repository.webhook_secret.length
      assert_requested :post, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks\z} do |req|
        body = URI.decode_www_form(req.body).to_h
        body["url"] == WEBHOOK_URL && body["pipeline_events"] == "true" && body["token"] == repository.webhook_secret
      end
    end

    test "remove deletes only the webhook whose url matches this deployment" do
      repository = create(:repository, full_name: "group/app", integration: @integration,
        scope: @project, webhook_secret: "existing-secret")

      stub_request(:get, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks\z})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: [
            gl_hook(id: 42, url: WEBHOOK_URL, pipeline_events: true),
            gl_hook(id: 99, url: "https://other.example.com/webhooks/other", pipeline_events: false)
          ].to_json)
      delete_42 = stub_request(:delete, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks/42\z})
        .to_return(status: 204)
      delete_99 = stub_request(:delete, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks/99\z})
        .to_return(status: 204)

      Gitlab::RepositoryService.new(@integration).remove(repository)

      assert_requested delete_42
      assert_not_requested delete_99
    end

    test "remove makes no GitLab call when webhook_secret is blank" do
      repository = create(:repository, full_name: "group/app", integration: @integration,
        scope: @project, webhook_secret: nil)

      hooks = stub_request(:get, %r{\A#{Regexp.escape(GITLAB_API)}/projects/#{ENCODED_APP}/hooks\z})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "[]")

      Gitlab::RepositoryService.new(@integration).remove(repository)

      assert_not_requested hooks
    end

    private

    def gl_project(path:, branch:, visibility:, description:)
      name = path.split("/").last
      {
        id: 278_964, description: description, name: name, path: name,
        name_with_namespace: path.split("/").map(&:capitalize).join(" / "),
        path_with_namespace: path, default_branch: branch, visibility: visibility,
        http_url_to_repo: "https://gitlab.com/#{path}.git",
        ssh_url_to_repo: "git@gitlab.com:#{path}.git",
        web_url: "https://gitlab.com/#{path}",
        created_at: "2020-01-15T08:00:00.000Z", last_activity_at: "2026-07-01T12:00:00.000Z",
        namespace: { id: 100, name: "Group", path: "group", kind: "group", full_path: "group" }
      }
    end

    def gl_branch(name)
      {
        name: name, merged: false, protected: name == "main", default: name == "main",
        web_url: "https://gitlab.com/group/app/-/tree/#{name}",
        commit: {
          id: "0" * 40, short_id: "0000000", title: "Init", message: "Init",
          author_name: "Alice Smith", authored_date: "2026-06-01T00:00:00.000Z"
        }
      }
    end

    def gl_hook(id:, url:, pipeline_events:)
      {
        id: id, url: url, project_id: 278_964, push_events: false,
        pipeline_events: pipeline_events, enable_ssl_verification: true,
        created_at: "2026-06-01T00:00:00.000Z"
      }
    end
  end
end
