# frozen_string_literal: true

require "test_helper"

class Web::Company::Sessions::ArtifactsControllerTest < ActionDispatch::IntegrationTest
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

    get company_session_artifacts_path(@session)
    assert_inertia_page "Company/Sessions/Artifacts"
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

    post review_company_session_artifacts_path(@session), params: {
      decisions: { asset.id.to_s => "dismiss" }
    }
    assert_response :redirect
  end

  test "review save activates session artifact when no existing asset" do
    artifact = create(
      :asset,
      name: "output.md",
      folder: "session-#{@session.id}",
      scope: @project,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review"
    )

    post review_company_session_artifacts_path(@session), params: {
      decisions: { artifact.id.to_s => "save" }
    }

    artifact.reload
    assert_equal "active", artifact.status
    assert_nil artifact.folder
    assert_includes Asset.accessible_from_project(@project), artifact
  end

  test "review save activates existing dismissed asset" do
    dismissed = create(
      :asset,
      name: "output.md",
      folder: nil,
      scope: @project,
      created_by: @user,
      status: "dismissed"
    )

    artifact = create(
      :asset,
      name: "output.md",
      folder: "session-#{@session.id}",
      scope: @project,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review"
    )

    post review_company_session_artifacts_path(@session), params: {
      decisions: { artifact.id.to_s => "save" }
    }

    dismissed.reload
    artifact.reload
    assert_equal "active", dismissed.status
    assert_equal "dismissed", artifact.status
    assert_includes Asset.accessible_from_project(@project), dismissed
  end
end
