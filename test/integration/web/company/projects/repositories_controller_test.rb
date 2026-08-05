# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders repositories page" do
    get company_project_repositories_path(@project)
    assert_inertia_page "Projects/Repositories/RepositoriesPage"
  end

  test "create redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "org/proj-repo", source_branch: "main", integration_id: integration.id }
    }
    assert_response :redirect

    repo = Repository.find_by(full_name: "org/proj-repo")
    assert_equal "https://github.com/org/proj-repo.git", repo.clone_url
  end

  test "create attaches a verified public repository without an integration" do
    fake = FakePublicRepositoryService.new
    PublicRepositoryService.stubs(:new).returns(fake)

    assert_difference("Repository.count", 1) do
      post company_project_repositories_path(@project), params: {
        repository: { public_url: "https://github.com/rails/rails", purpose: "Reference" }
      }
    end
    assert_response :redirect

    repo = Repository.find_by(full_name: "rails/rails")
    assert repo.public_source?
    assert_equal "https://github.com/rails/rails.git", repo.clone_url
    assert_equal "main", repo.source_branch
    assert_equal "Reference", repo.purpose
    assert_equal [ "https://github.com/rails/rails" ], fake.calls
  end

  test "create keeps the requested branch for a public repository" do
    PublicRepositoryService.stubs(:new).returns(FakePublicRepositoryService.new)

    post company_project_repositories_path(@project), params: {
      repository: { public_url: "https://github.com/rails/rails", source_branch: "7-1-stable" }
    }

    assert_equal "7-1-stable", Repository.find_by(full_name: "rails/rails").source_branch
  end

  test "create reports why a public repository could not be attached" do
    error = PublicRepositoryService::NotFound.new("Repository not found on GitHub, or it is not public")
    PublicRepositoryService.stubs(:new).returns(FakePublicRepositoryService.new(error: error))

    assert_no_difference("Repository.count") do
      post company_project_repositories_path(@project), params: {
        repository: { public_url: "https://github.com/acme/nope" }
      }
    end
    assert_response :redirect
    assert_equal "Repository not found on GitHub, or it is not public", session["inertia_errors"][:public_url]
  end

  test "create ignores a client-supplied clone url" do
    integration = create(:integration, company: @company, connected_by: @user)

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "org/proj-repo", source_branch: "main", integration_id: integration.id,
                     clone_url: "https://attacker.example/evil.git" }
    }

    assert_equal "https://github.com/org/proj-repo.git", Repository.find_by(full_name: "org/proj-repo").clone_url
  end

  test "update redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)

    patch company_project_repository_path(@project, repo), params: {
      repository: { source_branch: "develop" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    integration = create(:integration, company: @company, connected_by: @user)
    repo = create(:repository, integration: integration, scope: @project)

    delete company_project_repository_path(@project, repo)
    assert_response :redirect
  end
end
