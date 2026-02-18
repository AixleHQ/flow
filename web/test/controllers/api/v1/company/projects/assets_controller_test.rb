# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::AssetsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin)

    @project_asset = create(:asset, scope: @project, created_by: @admin, name: "project-doc.md")
    @project_version = create(:asset_version, :with_file, asset: @project_asset, uploaded_by: @admin, version: 1)

    @company_asset = create(:asset, scope: @company, created_by: @admin, name: "company-doc.md")
    @company_version = create(:asset_version, :with_file, asset: @company_asset, uploaded_by: @admin, version: 1)
  end

  # ====== SHOW Tests ======

  test "#show returns project-scoped asset with versions" do
    sign_in @admin

    get :show, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :success
    json = response.parsed_body
    data = json["data"]
    assert { data["id"] == @project_asset.id }
    assert { data["name"] == "project-doc.md" }
    assert { data["versions"].length == 1 }
  end

  test "#show returns company-scoped asset visible to project" do
    sign_in @admin

    get :show, params: { project_id: @project.id, id: @company_asset.id }

    assert_response :success
    json = response.parsed_body
    assert { json["data"]["id"] == @company_asset.id }
  end

  test "#show returns 404 for asset from another company" do
    other_company = create(:company, email_domain: "other.com")
    other_asset = create(:asset, scope: other_company, created_by: create(:user, company: other_company))

    sign_in @admin

    get :show, params: { project_id: @project.id, id: other_asset.id }

    assert_response :not_found
  end

  # ====== DOWNLOAD Tests ======

  test "#download redirects for project asset" do
    sign_in @admin

    get :download, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :redirect
  end

  test "#download redirects for company asset via project context" do
    sign_in @admin

    get :download, params: { project_id: @project.id, id: @company_asset.id }

    assert_response :redirect
  end

  test "#download with specific version" do
    v2 = create(:asset_version, :with_file, asset: @project_asset, uploaded_by: @admin, version: 2)
    sign_in @admin

    get :download, params: { project_id: @project.id, id: @project_asset.id, version: 2 }

    assert_response :redirect
  end

  test "#download returns 404 for missing version" do
    sign_in @admin

    get :download, params: { project_id: @project.id, id: @project_asset.id, version: 999 }

    assert_response :not_found
  end

  test "#download requires project access" do
    non_collaborator = create(:user, :employee, company: @company)
    sign_in non_collaborator

    get :download, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :forbidden
  end

  test "#download requires authentication" do
    get :download, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :unauthorized
  end

  # ====== VERSIONS Tests ======

  test "#versions returns versions for project asset" do
    v2 = create(:asset_version, :with_file, asset: @project_asset, uploaded_by: @admin, version: 2)
    sign_in @admin

    get :versions, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :success
    json = response.parsed_body
    items = json["items"]
    assert { items.length == 2 }
    assert { items.first["version"] == 2 }
  end

  test "#versions returns versions for company asset via project" do
    sign_in @admin

    get :versions, params: { project_id: @project.id, id: @company_asset.id }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
  end

  test "#versions includes serializer fields" do
    sign_in @admin

    get :versions, params: { project_id: @project.id, id: @project_asset.id }

    json = response.parsed_body
    v = json["items"].first
    assert { v.key?("file_url") }
    assert { v.key?("source") }
    assert { v.key?("version") }
  end

  test "#versions requires project access" do
    non_collaborator = create(:user, :employee, company: @company)
    sign_in non_collaborator

    get :versions, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :forbidden
  end

  test "#versions requires authentication" do
    get :versions, params: { project_id: @project.id, id: @project_asset.id }

    assert_response :unauthorized
  end
end
