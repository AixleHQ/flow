# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::Sessions::ArtifactsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :agent_session, user: @user, project: @project)
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the artifacts page" do
    create(
      :asset,
      name: "session-out.md",
      scope: @project,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review"
    )

    get company_project_session_artifacts_path(@project, @session)

    assert_response :success
    assert_inertia_page "Projects/Sessions/ArtifactsPage"
  end
end
