# frozen_string_literal: true

require "test_helper"

module Github
  class RepositoryServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :employee, company: @company)
      @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
    end

    test "list_available returns repos from GitHub API" do
      mock_token_service = mock("token_service")
      mock_token_service.expects(:generate_installation_token).returns("ghs_test")
      Github::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      mock_client = mock("octokit_client")
      repos = [
        OpenStruct.new(full_name: "org/app", default_branch: "main", clone_url: "https://github.com/org/app.git", private: false, description: "Main app"),
        OpenStruct.new(full_name: "org/lib", default_branch: "develop", clone_url: "https://github.com/org/lib.git", private: true, description: nil)
      ]
      mock_client.expects(:auto_paginate=).with(true)
      mock_client.expects(:list_app_installation_repositories).returns({ repositories: repos })
      Octokit::Client.expects(:new).with(access_token: "ghs_test").returns(mock_client)

      result = Github::RepositoryService.new(@integration).list_available
      assert_equal 2, result.length
      assert_equal "org/app", result[0][:full_name]
      assert_equal false, result[0][:is_private]
      assert_equal "org/lib", result[1][:full_name]
      assert_equal true, result[1][:is_private]
    end

    test "list_available returns empty array on error" do
      mock_token_service = mock("token_service")
      mock_token_service.expects(:generate_installation_token).raises(Octokit::Unauthorized.new(method: :get, status: 401))
      Github::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      result = Github::RepositoryService.new(@integration).list_available
      assert_equal [], result
    end

    test "find_repo returns single repo info" do
      mock_token_service = mock("token_service")
      mock_token_service.expects(:generate_installation_token).returns("ghs_test")
      Github::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      mock_client = mock("octokit_client")
      repo = OpenStruct.new(full_name: "org/app", default_branch: "main", clone_url: "https://github.com/org/app.git", private: false, description: "Main app")
      mock_client.expects(:repository).with("org/app").returns(repo)
      Octokit::Client.expects(:new).with(access_token: "ghs_test").returns(mock_client)

      result = Github::RepositoryService.new(@integration).find_repo("org/app")
      assert_equal "org/app", result[:full_name]
      assert_equal "main", result[:default_branch]
    end

    test "find_repo returns nil on error" do
      mock_token_service = mock("token_service")
      mock_token_service.expects(:generate_installation_token).returns("ghs_test")
      Github::TokenService.expects(:new).with(@integration).returns(mock_token_service)

      mock_client = mock("octokit_client")
      mock_client.expects(:repository).raises(Octokit::NotFound.new(method: :get, status: 404))
      Octokit::Client.expects(:new).with(access_token: "ghs_test").returns(mock_client)

      result = Github::RepositoryService.new(@integration).find_repo("org/nonexistent")
      assert_nil result
    end
  end
end
