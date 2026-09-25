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

  test "the edit dialog is handed the repository's branches" do
    integration = create(:integration, :active, company: @company, connected_by: @user)
    repo = create(:repository, full_name: "org/app", scope: @project, integration: integration)
    branches = Struct.new(:names) { def list_branches(_full_name) = names }.new(%w[main release])
    RepositoryService.stubs(:for).with(integration).returns(branches)

    # The dialog's own request: a partial reload naming the prop the way the client sees it.
    get company_project_repositories_path(@project, edit_repo_id: repo.id),
        headers: { "X-Inertia" => "true", "X-Inertia-Partial-Component" => "Projects/Repositories/RepositoriesPage",
                   "X-Inertia-Partial-Data" => "editBranches" }

    assert_equal %w[main release], response.parsed_body.dig("props", "editBranches")
    assert_nil response.parsed_body.dig("props", "repositories"), "a partial reload returns only what it asked for"
  end

  test "create redirects on success" do
    integration = create(:integration, company: @company, connected_by: @user)
    RepositoryService.stubs(:for).returns(FakeGithub::RepositoryService.new(integration))

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "org/proj-repo", source_branch: "main", integration_id: integration.id }
    }
    assert_response :redirect

    repo = Repository.find_by(full_name: "org/proj-repo")
    assert_equal "https://github.com/org/proj-repo.git", repo.clone_url
  end

  test "a repository added through a connection takes its visibility from the code host" do
    integration = create(:integration, company: @company, connected_by: @user)
    RepositoryService.stubs(:for).with(integration).returns(FakeGithub::RepositoryService.new(integration))

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "acme/infra", source_branch: "develop", integration_id: integration.id }
    }

    assert Repository.find_by(full_name: "acme/infra").is_private
  end

  test "a repository whose visibility cannot be looked up is still added" do
    integration = create(:integration, company: @company, connected_by: @user)
    RepositoryService.stubs(:for).raises(Github::TokenService::ConfigurationError, "GitHub App ID not configured")

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "acme/infra", source_branch: "develop", integration_id: integration.id }
    }

    assert_not Repository.find_by!(full_name: "acme/infra").is_private
  end

  test "another company's connection is never asked about a repository" do
    other = create(:company)
    foreign = create(:integration, company: other, connected_by: create(:user, company: other))
    RepositoryService.expects(:for).never

    post company_project_repositories_path(@project), params: {
      repository: { full_name: "acme/infra", source_branch: "develop", integration_id: foreign.id }
    }

    assert_nil Repository.find_by(full_name: "acme/infra")
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
