# frozen_string_literal: true

require "test_helper"

# Behavior (not authorization — see assets_authorization_test.rb) of the API
# project-assets `update` (single move) and `bulk_actions` (multi move/delete)
# endpoints, added for the Assets folder view's drag-and-drop / multi-select bar.
class Api::V1::Projects::AssetsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    sign_in_as(@owner)
  end

  test "update moves an asset to a different folder" do
    asset = create(:asset, folder: "docs", scope: @project, created_by: @owner)

    patch api_v1_project_asset_path(@project, asset), params: { asset: { folder: "archive" } }, as: :json

    assert_response :success
    assert_equal "archive", response.parsed_body["folder"]
    assert_equal "archive", asset.reload.folder
  end

  test "update to a blank folder moves an asset to the root" do
    asset = create(:asset, folder: "docs", scope: @project, created_by: @owner)

    patch api_v1_project_asset_path(@project, asset), params: { asset: { folder: "" } }, as: :json

    assert_response :success
    assert_nil asset.reload.folder
  end

  test "update returns 422 when the destination already has an asset with the same name" do
    create(:asset, name: "readme.md", folder: "archive", scope: @project, created_by: @owner)
    moving = create(:asset, name: "readme.md", folder: "docs", scope: @project, created_by: @owner)

    patch api_v1_project_asset_path(@project, moving), params: { asset: { folder: "archive" } }, as: :json

    assert_response :unprocessable_entity
    assert { response.parsed_body["error"].present? }
    assert_equal "docs", moving.reload.folder
  end

  test "update refuses to move a company-scoped asset from project context" do
    company_asset = create(:asset, scope: @company, created_by: @owner)

    patch api_v1_project_asset_path(@project, company_asset), params: { asset: { folder: "x" } }, as: :json

    assert_response :not_found
  end

  test "bulk_actions moves several assets at once" do
    a = create(:asset, folder: nil, scope: @project, created_by: @owner)
    b = create(:asset, folder: "old", scope: @project, created_by: @owner)

    post bulk_actions_api_v1_project_assets_path(@project),
         params: { action_type: "move", asset_ids: [ a.id, b.id ], folder: "new" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ a.id, b.id ].sort, body["succeeded"].sort
    assert_empty body["skipped"]
    assert_equal "new", a.reload.folder
    assert_equal "new", b.reload.folder
  end

  test "bulk_actions deletes several assets at once" do
    a = create(:asset, scope: @project, created_by: @owner)
    b = create(:asset, scope: @project, created_by: @owner)

    post bulk_actions_api_v1_project_assets_path(@project),
         params: { action_type: "delete", asset_ids: [ a.id, b.id ] }, as: :json

    assert_response :success
    assert { a.reload.deleted? }
    assert { b.reload.deleted? }
  end

  test "bulk_actions reports a company-scoped id as skipped rather than failing the batch" do
    own = create(:asset, folder: nil, scope: @project, created_by: @owner)
    company_asset = create(:asset, scope: @company, created_by: @owner)

    post bulk_actions_api_v1_project_assets_path(@project),
         params: { action_type: "move", asset_ids: [ own.id, company_asset.id ], folder: "x" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ own.id ], body["succeeded"]
    assert_equal [ company_asset.id ], body["skipped"].map { |s| s["id"] }
  end

  test "bulk_actions returns 400 for an unknown action_type" do
    asset = create(:asset, scope: @project, created_by: @owner)

    post bulk_actions_api_v1_project_assets_path(@project),
         params: { action_type: "obliterate", asset_ids: [ asset.id ] }, as: :json

    assert_response :bad_request
  end

  test "bulk_actions returns 400 when asset_ids is empty" do
    post bulk_actions_api_v1_project_assets_path(@project), params: { action_type: "delete", asset_ids: [] }, as: :json

    assert_response :bad_request
  end
end
