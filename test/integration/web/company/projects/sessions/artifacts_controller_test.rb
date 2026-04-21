# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::Sessions::ArtifactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, user: @user, project: @project)
    sign_in_as(@user)
  end

  test "index renders artifacts page" do
    create(
      :asset,
      name: "session-out.md",
      scope: @project,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review"
    )

    get company_project_session_artifacts_path(@project, @session)
    assert_inertia_page "Projects/Sessions/ArtifactsPage"
  end

  test "review redirects on success" do
    asset = create(
      :asset,
      name: "review-me.md",
      scope: @project,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review"
    )

    post review_company_project_session_artifacts_path(@project, @session), params: {
      decisions: { asset.id.to_s => "dismiss" }
    }
    assert_response :redirect
  end
end
