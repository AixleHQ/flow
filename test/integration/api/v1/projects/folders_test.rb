# frozen_string_literal: true

require "test_helper"

# Behavior (not authorization — see folders_authorization_test.rb) of the API
# project-folders endpoints: success shapes and the FolderService error
# mappings (docs/testing.md §2, "Request: ... status, ... Inertia contract" —
# these are plain JSON, so the contract here is the response status/body).
class Api::V1::Projects::FoldersTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @owner = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @owner)
    sign_in_as(@owner)
  end

  test "create returns 201 with the new folder" do
    post api_v1_project_folders_path(@project), params: { folder: { path: "dashboard" } }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "dashboard", body["path"]
    assert_equal "project", body["scopeIndicator"]
    assert { Folder.for_project(@project).exists?(path: "dashboard") }
  end

  test "create returns 422 when the parent folder does not exist" do
    post api_v1_project_folders_path(@project), params: { folder: { path: "dashboard/specs" } }, as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  test "create returns 422 when the name collides with an existing sibling" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)

    post api_v1_project_folders_path(@project), params: { folder: { path: "dashboard" } }, as: :json

    assert_response :unprocessable_entity
  end

  test "relocate renames a folder and cascades to its assets" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    asset = create(:asset, name: "a.md", folder: "dashboard", scope: @project, created_by: @owner)

    patch api_v1_project_folders_relocate_path(@project),
          params: { from_path: "dashboard", to_path: "dash" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "dashboard", body["from"]
    assert_equal "dash", body["to"]
    assert_equal "dash", asset.reload.folder
  end

  test "relocate returns 404 for a folder that does not exist in the project" do
    patch api_v1_project_folders_relocate_path(@project),
          params: { from_path: "ghost", to_path: "renamed" }, as: :json

    assert_response :not_found
  end

  test "destroy removes an empty folder" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)

    delete api_v1_project_folders_path(@project), params: { path: "dashboard" }, as: :json

    assert_response :success
    assert { Folder.for_project(@project).count.zero? }
  end

  test "destroy returns 422 with the item count for a non-empty folder" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    create(:asset, name: "a.md", folder: "dashboard", scope: @project, created_by: @owner)

    delete api_v1_project_folders_path(@project), params: { path: "dashboard" }, as: :json

    assert_response :unprocessable_entity
    assert_equal 1, response.parsed_body["itemCount"]
    assert { Folder.for_project(@project).exists?(path: "dashboard") }
  end

  test "destroy with recursive: true soft-deletes nested assets and removes nested folders" do
    create(:folder, path: "dashboard", scope: @project, created_by: @owner)
    create(:folder, path: "dashboard/specs", scope: @project, created_by: @owner)
    asset = create(:asset, name: "a.md", folder: "dashboard/specs", scope: @project, created_by: @owner)

    delete api_v1_project_folders_path(@project), params: { path: "dashboard", recursive: true }, as: :json

    assert_response :success
    assert { Folder.for_project(@project).count.zero? }
    assert { asset.reload.deleted_at.present? }
  end
end
