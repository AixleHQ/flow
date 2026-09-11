# frozen_string_literal: true

require "test_helper"

# Behavior (not authorization — see assets_authorization_test.rb) of the
# company-level API assets `update` (single move) and `bulk_actions`
# (multi move/delete) endpoints.
class Api::V1::Company::AssetsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@owner)
  end

  test "update moves an asset to a different folder" do
    asset = create(:asset, folder: "docs", scope: @company, created_by: @owner)

    patch api_v1_company_asset_path(asset), params: { asset: { folder: "archive" } }, as: :json

    assert_response :success
    assert_equal "archive", asset.reload.folder
  end

  test "bulk_actions moves several assets at once" do
    a = create(:asset, folder: nil, scope: @company, created_by: @owner)
    b = create(:asset, folder: "old", scope: @company, created_by: @owner)

    post bulk_actions_api_v1_company_assets_path,
         params: { action_type: "move", asset_ids: [ a.id, b.id ], folder: "new" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ a.id, b.id ].sort, body["succeeded"].sort
    assert_equal "new", a.reload.folder
    assert_equal "new", b.reload.folder
  end

  test "bulk_actions deletes several assets at once" do
    a = create(:asset, scope: @company, created_by: @owner)
    b = create(:asset, scope: @company, created_by: @owner)

    post bulk_actions_api_v1_company_assets_path, params: { action_type: "delete", asset_ids: [ a.id, b.id ] }, as: :json

    assert_response :success
    assert { a.reload.deleted? }
    assert { b.reload.deleted? }
  end
end
