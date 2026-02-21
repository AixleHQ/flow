# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::TerminalSessions::ArtifactsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :collected, user: @user, project: @project)

    @pending_asset = create(:asset,
      name: "report.md",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review",
      folder: "session-#{@session.id}"
    )
    create(:asset_version, :with_file, asset: @pending_asset, uploaded_by: @user)

    @active_asset = create(:asset,
      name: "existing.md",
      scope: @company,
      created_by: @user,
      status: "active"
    )
  end

  # ====== INDEX Tests ======

  test "#index returns pending_review assets for session" do
    sign_in @user

    get :index, params: { terminal_session_id: @session.id }

    assert_response :success
    json = response.parsed_body
    items = json["items"] || json
    names = Array(items).map { |a| a["name"] }
    assert_includes names, "report.md"
    refute_includes names, "existing.md"
  end

  test "#index returns empty for session with no pending assets" do
    sign_in @user
    other_session = create(:terminal_session, :collected, user: @user)

    get :index, params: { terminal_session_id: other_session.id }

    assert_response :success
    json = response.parsed_body
    items = json["items"] || json
    assert_equal 0, Array(items).length
  end

  test "#index requires authentication" do
    get :index, params: { terminal_session_id: @session.id }

    assert_response :unauthorized
  end

  test "#index returns 404 for session from other company" do
    sign_in @user
    other_company = create(:company, email_domain: "other.com")
    other_user = create(:user, :admin, company: other_company)
    other_session = create(:terminal_session, user: other_user)

    get :index, params: { terminal_session_id: other_session.id }

    assert_response :not_found
  end

  # ====== REVIEW Tests ======

  test "#review saves asset and marks session reviewed" do
    sign_in @user

    post :review, params: {
      terminal_session_id: @session.id,
      decisions: { @pending_asset.id.to_s => "save" },
      target_scope_type: "Project",
      target_scope_id: @project.id
    }, as: :json

    assert_response :success
    @pending_asset.reload
    assert_equal "active", @pending_asset.status
    # Controller does not update scope; asset keeps original scope
    assert_equal "Company", @pending_asset.scope_type
    assert_equal @company.id, @pending_asset.scope_id
    assert_nil @pending_asset.folder
    assert_not_nil @pending_asset.reviewed_at

    @session.reload
    assert @session.artifacts_reviewed
  end

  test "#review dismisses asset" do
    sign_in @user

    post :review, params: {
      terminal_session_id: @session.id,
      decisions: { @pending_asset.id.to_s => "dismiss" },
      target_scope_type: "Company",
      target_scope_id: @company.id
    }, as: :json

    assert_response :success
    @pending_asset.reload
    assert_equal "dismissed", @pending_asset.status
    assert_not_nil @pending_asset.reviewed_at
  end

  test "#review handles mixed save and dismiss" do
    sign_in @user
    asset2 = create(:asset,
      name: "data.json",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review",
      folder: "session-#{@session.id}"
    )
    create(:asset_version, :with_file, asset: asset2, uploaded_by: @user)

    post :review, params: {
      terminal_session_id: @session.id,
      decisions: {
        @pending_asset.id.to_s => "save",
        asset2.id.to_s => "dismiss"
      },
      target_scope_type: "Company",
      target_scope_id: @company.id
    }, as: :json

    assert_response :success
    @pending_asset.reload
    assert_equal "active", @pending_asset.status
    asset2.reload
    assert_equal "dismissed", asset2.status
  end

  test "#review requires authentication" do
    post :review, params: {
      terminal_session_id: @session.id,
      decisions: { @pending_asset.id.to_s => "save" },
      target_scope_type: "Company",
      target_scope_id: @company.id
    }, as: :json

    assert_response :unauthorized
  end

  # ====== DOWNLOAD Tests ======

  test "#download redirects to file" do
    sign_in @user

    get :download, params: {
      terminal_session_id: @session.id,
      id: @pending_asset.id
    }

    assert_response :redirect
  end

  test "#download requires authentication" do
    get :download, params: {
      terminal_session_id: @session.id,
      id: @pending_asset.id
    }

    assert_response :unauthorized
  end
end
