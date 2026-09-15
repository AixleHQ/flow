# frozen_string_literal: true

require "test_helper"

# Behavior (not authorization — see folders_authorization_test.rb) of the
# company-level API folders endpoints.
class Api::V1::Company::FoldersTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@owner)
  end

  test "create returns 201 with the new folder" do
    post api_v1_company_folders_path, params: { folder: { path: "shared" } }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "shared", body["path"]
    assert_equal "company", body["scopeIndicator"]
    assert { Folder.for_company(@company).exists?(path: "shared") }
  end

  test "relocate renames a folder" do
    create(:folder, path: "shared", scope: @company, created_by: @owner)

    patch api_v1_company_folders_relocate_path, params: { from_path: "shared", to_path: "common" }, as: :json

    assert_response :success
    assert { Folder.for_company(@company).exists?(path: "common") }
  end

  test "destroy returns 422 with the item count for a non-empty folder" do
    create(:folder, path: "shared", scope: @company, created_by: @owner)
    create(:asset, name: "a.md", folder: "shared", scope: @company, created_by: @owner)

    delete api_v1_company_folders_path, params: { path: "shared" }, as: :json

    assert_response :unprocessable_entity
    assert_equal 1, response.parsed_body["itemCount"]
  end

  test "destroy with recursive: true soft-deletes nested assets" do
    create(:folder, path: "shared", scope: @company, created_by: @owner)
    asset = create(:asset, name: "a.md", folder: "shared", scope: @company, created_by: @owner)

    delete api_v1_company_folders_path, params: { path: "shared", recursive: true }, as: :json

    assert_response :success
    assert { asset.reload.deleted_at.present? }
  end
end
