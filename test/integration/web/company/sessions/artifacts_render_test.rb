# frozen_string_literal: true

require "test_helper"

class Web::Company::Sessions::ArtifactsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # the artifacts list trips the unused-eager-loading gate
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the artifacts page" do
    # Session is in company_sessions_scope because it is owned by a company user.
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    # Only pending_review/active output assets are listed by the controller.
    create(:asset, terminal_session: session, scope: @company, status: "pending_review", created_by: @user)

    get company_session_artifacts_path(session)
    assert_response :success
    assert_inertia_page "Company/Sessions/Artifacts"
  end
end
