# frozen_string_literal: true

require "test_helper"

module Gitlab
  class RepositoryServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)

      Settings.stubs(:gitlab).returns(
        OpenStruct.new(endpoint: "https://gitlab.com/api/v4")
      )
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("palad.example.com")
    end

    test "list_available returns repos from GitLab API" do
      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.expects(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      projects = [
        OpenStruct.new(path_with_namespace: "group/app", default_branch: "main",
          http_url_to_repo: "https://gitlab.com/group/app.git",
          visibility: "private", description: "Main app"),
        OpenStruct.new(path_with_namespace: "group/lib", default_branch: "develop",
          http_url_to_repo: "https://gitlab.com/group/lib.git",
          visibility: "public", description: nil)
      ]
      mock_client.expects(:projects).with(membership: true, per_page: 100, auto_paginate: true).returns(projects)

      result = Gitlab::RepositoryService.new(@integration).list_available

      assert_equal 2, result.length
      assert_equal "group/app", result[0][:full_name]
      assert_equal true, result[0][:is_private]
      assert_equal "group/lib", result[1][:full_name]
      assert_equal false, result[1][:is_private]
    end

    test "list_available returns empty array on error" do
      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.expects(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)
      mock_response = OpenStruct.new(code: 401, parsed_response: '{"message":"401 Unauthorized"}',
        request: OpenStruct.new(base_uri: "https://gitlab.com/api/v4", path: "/api/v4/projects"))
      mock_client.expects(:projects).raises(::Gitlab::Error::Unauthorized.new(mock_response))

      result = Gitlab::RepositoryService.new(@integration).list_available
      assert_equal [], result
    end

    test "find_repo returns single repo info" do
      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.expects(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      proj = OpenStruct.new(path_with_namespace: "group/app", default_branch: "main",
        http_url_to_repo: "https://gitlab.com/group/app.git",
        visibility: "private", description: "Main app")
      mock_client.expects(:project).with("group/app").returns(proj)

      result = Gitlab::RepositoryService.new(@integration).find_repo("group/app")

      assert_equal "group/app", result[:full_name]
      assert_equal "main", result[:default_branch]
      assert_equal "https://gitlab.com/group/app.git", result[:clone_url]
    end

    test "find_repo returns nil on error" do
      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.expects(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)
      mock_response = OpenStruct.new(code: 404, parsed_response: '{"message":"404 Not Found"}',
        request: OpenStruct.new(base_uri: "https://gitlab.com/api/v4", path: "/api/v4/projects/group%2Fnonexistent"))
      mock_client.expects(:project).raises(::Gitlab::Error::NotFound.new(mock_response))

      result = Gitlab::RepositoryService.new(@integration).find_repo("group/nonexistent")
      assert_nil result
    end

    test "list_branches returns branch names" do
      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.expects(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      branches = [ OpenStruct.new(name: "main"), OpenStruct.new(name: "develop") ]
      mock_client.expects(:branches).with("group/app").returns(branches)

      result = Gitlab::RepositoryService.new(@integration).list_branches("group/app")
      assert_equal %w[main develop], result
    end

    test "configure_webhook generates secret and calls GitLab API" do
      repository = create(:repository, full_name: "group/app", integration: @integration, scope: @company)

      mock_token_service = mock("token_service")
      mock_client = mock("gitlab_client")
      mock_token_service.stubs(:client).returns(mock_client)
      Gitlab::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      mock_client.expects(:add_project_hook).with(
        "group/app",
        "https://palad.example.com/webhooks/gitlab",
        token: anything,
        pipeline_events: true
      )

      Gitlab::RepositoryService.new(@integration).configure_webhook(repository)
      repository.reload

      assert_not_nil repository.webhook_secret
      assert_equal 64, repository.webhook_secret.length
    end
  end
end
