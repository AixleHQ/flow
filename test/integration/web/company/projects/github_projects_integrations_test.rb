# frozen_string_literal: true

require "test_helper"

# Choosing the GitHub projects an App connection covers, through the real
# endpoints; the GitHub API behind them is FakeGithub::ProjectsApi.
class Web::Company::Projects::GithubProjectsIntegrationsTest < ActionDispatch::IntegrationTest
  setup do
    @github = stub_github_projects!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @integration = create(:integration, :github_projects, :active, company: @company, project: @project, connected_by: @user)
    sign_in_as(@user)
  end

  test "the picker lists the organization's open projects and the ones already chosen" do
    get github_projects_company_project_integration_path(@project, @integration), as: :json

    assert_response :success
    assert_equal [ %w[Roadmap Ops], [ FakeGithub::ProjectsApi::ROADMAP ] ],
                 [ response.parsed_body["projects"].pluck("title"), response.parsed_body["selected"] ]
  end

  test "a permission the App lacks is reported to the picker" do
    @github.fail_next(:projects, Trackers::Error.new("Resource not accessible by integration", code: "permission_denied"))

    get github_projects_company_project_integration_path(@project, @integration), as: :json

    assert_response :unprocessable_content
    assert_equal "permission_denied", response.parsed_body["error"]
  end

  test "saving the projects provisions their trackers; an empty choice detaches them" do
    patch company_project_integration_path(@project, @integration), params: { github_project_ids: [ FakeGithub::ProjectsApi::OPS ] }

    assert_equal "GitHub projects saved", flash[:notice]
    assert_equal({ "Ops" => "active" }, ProjectTracker.for_project(@project).pluck(:name, :status).to_h)

    patch company_project_integration_path(@project, @integration), params: { github_project_ids: [] }, as: :json
    assert_equal({ "Ops" => "detached" }, ProjectTracker.for_project(@project).pluck(:name, :status).to_h)
  end
end
