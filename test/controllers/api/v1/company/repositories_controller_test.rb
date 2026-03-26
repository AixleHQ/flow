# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::RepositoriesControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @integration = create(:integration, :github, :active, company: @company, connected_by: @admin)
    @gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @admin)
    @repo = create(:repository, full_name: "org/app", scope: @company, integration: @integration)
    @gitlab_repo = create(:repository, full_name: "group/gl-app", scope: @company,
      integration: @gitlab_integration, webhook_secret: "test-secret-abc")
  end

  # ====== INDEX ======

  test "#index returns company repositories for any user" do
    sign_in @employee
    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 2 }
    assert { json["items"].map { |r| r["full_name"] }.include?("org/app") }
  end

  test "#index requires authentication" do
    get :index
    assert_response :unauthorized
  end

  # ====== SHOW ======

  test "#show returns repository" do
    sign_in @employee
    get :show, params: { id: @repo.id }

    assert_response :success
    json = response.parsed_body
    assert { json["data"]["full_name"] == "org/app" }
    assert { json["data"]["scope_indicator"] == "company" }
  end

  # ====== CREATE ======

  test "#create adds repository for admin" do
    sign_in @admin
    Github::RepositoryService.any_instance.expects(:find_repo).with("org/new-repo").returns({
      full_name: "org/new-repo",
      default_branch: "main",
      clone_url: "https://github.com/org/new-repo.git",
      is_private: false,
      description: "New repo"
    })

    assert_difference("Repository.count", 1) do
      post :create, params: { integration_id: @integration.id, full_name: "org/new-repo" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["full_name"] == "org/new-repo" }
  end

  test "#create returns error when repo not found on GitHub" do
    sign_in @admin
    Github::RepositoryService.any_instance.expects(:find_repo).returns(nil)

    post :create, params: { integration_id: @integration.id, full_name: "org/nonexistent" }
    assert_response :unprocessable_entity
  end

  test "#create with gitlab integration configures webhook" do
    sign_in @admin
    Gitlab::RepositoryService.any_instance.expects(:find_repo).with("group/new-repo").returns({
      full_name: "group/new-repo",
      default_branch: "main",
      clone_url: "https://gitlab.com/group/new-repo.git",
      is_private: false,
      description: "GitLab repo"
    })
    Gitlab::RepositoryService.any_instance.expects(:configure).once

    assert_difference("Repository.count", 1) do
      post :create, params: { integration_id: @gitlab_integration.id, full_name: "group/new-repo" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["full_name"] == "group/new-repo" }
  end

  test "#create requires admin" do
    sign_in @employee
    post :create, params: { integration_id: @integration.id, full_name: "org/new" }
    assert_response :forbidden
  end

  # ====== DESTROY ======

  test "#destroy removes repository for admin" do
    sign_in @admin
    Github::RepositoryService.any_instance.expects(:remove).once
    assert_difference("Repository.count", -1) do
      delete :destroy, params: { id: @repo.id }
    end
    assert_response :success
  end

  test "#destroy calls remove on gitlab repository" do
    sign_in @admin
    Gitlab::RepositoryService.any_instance.expects(:remove).once
    assert_difference("Repository.count", -1) do
      delete :destroy, params: { id: @gitlab_repo.id }
    end
    assert_response :success
  end

  test "#destroy requires admin" do
    sign_in @employee
    delete :destroy, params: { id: @repo.id }
    assert_response :forbidden
  end

  # ====== AVAILABLE ======

  test "#available returns available repos for admin" do
    sign_in @admin
    Github::RepositoryService.any_instance.expects(:list_available).returns([
      { full_name: "org/app", default_branch: "main", clone_url: "https://...", is_private: false, description: nil }
    ])

    get :available, params: { integration_id: @integration.id }
    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
  end

  test "#available requires admin" do
    sign_in @employee
    get :available, params: { integration_id: @integration.id }
    assert_response :forbidden
  end
end
