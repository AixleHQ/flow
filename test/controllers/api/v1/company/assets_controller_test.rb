# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::AssetsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)

    @asset = create(:asset, scope: @company, created_by: @admin, name: "report.md")
    @version1 = create(:asset_version, :with_file, asset: @asset, uploaded_by: @admin, version: 1)
    @version2 = create(:asset_version, :with_file, asset: @asset, uploaded_by: @admin, version: 2)
  end

  # ====== SHOW Tests ======

  test "#show returns asset with all versions for admin" do
    sign_in @admin

    get :show, params: { id: @asset.id }

    assert_response :success
    json = response.parsed_body
    data = json["data"]
    assert { data["id"] == @asset.id }
    assert { data["name"] == "report.md" }
    assert { data["versions"].length == 2 }
    assert { data["versions"].first["version"] == 2 }
    assert { data["versions"].last["version"] == 1 }
  end

  test "#show returns versions with file_url" do
    sign_in @admin

    get :show, params: { id: @asset.id }

    json = response.parsed_body
    versions = json["data"]["versions"]
    versions.each do |v|
      assert { v.key?("file_url") }
      assert { v.key?("source") }
    end
  end

  test "#show requires admin role" do
    sign_in @employee

    get :show, params: { id: @asset.id }

    assert_response :forbidden
  end

  test "#show requires authentication" do
    get :show, params: { id: @asset.id }

    assert_response :unauthorized
  end

  # ====== DOWNLOAD Tests ======

  test "#download redirects to file for latest version" do
    sign_in @admin

    get :download, params: { id: @asset.id }

    assert_response :redirect
  end

  test "#download redirects to specific version" do
    sign_in @admin

    get :download, params: { id: @asset.id, version: 1 }

    assert_response :redirect
  end

  test "#download returns 404 for non-existent version" do
    sign_in @admin

    get :download, params: { id: @asset.id, version: 999 }

    assert_response :not_found
  end

  test "#download requires admin role" do
    sign_in @employee

    get :download, params: { id: @asset.id }

    assert_response :forbidden
  end

  test "#download requires authentication" do
    get :download, params: { id: @asset.id }

    assert_response :unauthorized
  end

  # ====== VERSIONS Tests ======

  test "#versions returns all versions ordered desc" do
    sign_in @admin

    get :versions, params: { id: @asset.id }

    assert_response :success
    json = response.parsed_body
    items = json["items"]
    assert { items.length == 2 }
    assert { items.first["version"] == 2 }
    assert { items.last["version"] == 1 }
  end

  test "#versions includes file_url and source" do
    sign_in @admin

    get :versions, params: { id: @asset.id }

    json = response.parsed_body
    items = json["items"]
    items.each do |v|
      assert { v.key?("file_url") }
      assert { v.key?("source") }
      assert { v.key?("content_type") }
      assert { v.key?("file_size") }
      assert { v.key?("uploaded_by_id") }
    end
  end

  test "#versions requires admin role" do
    sign_in @employee

    get :versions, params: { id: @asset.id }

    assert_response :forbidden
  end

  test "#versions requires authentication" do
    get :versions, params: { id: @asset.id }

    assert_response :unauthorized
  end

  # ====== DESTROY (soft delete) Tests ======

  test "#destroy soft-deletes asset" do
    sign_in @admin

    delete :destroy, params: { id: @asset.id }

    assert_response :success
    @asset.reload
    assert { @asset.deleted_at.present? }
  end

  test "#destroy hides asset from active-filtered index" do
    sign_in @admin

    delete :destroy, params: { id: @asset.id }

    get :index, params: { q: { deleted_at_null: "1" } }
    json = response.parsed_body
    ids = json["items"].map { |a| a["id"] }
    assert { !ids.include?(@asset.id) }
  end

  # ====== RESTORE Tests ======

  test "#restore clears deleted_at" do
    sign_in @admin
    @asset.soft_delete!

    post :restore, params: { id: @asset.id }

    assert_response :success
    @asset.reload
    assert { @asset.deleted_at.nil? }
  end

  test "#restore requires admin" do
    sign_in @employee
    @asset.soft_delete!

    post :restore, params: { id: @asset.id }

    assert_response :forbidden
  end

  test "#restore requires authentication" do
    @asset.soft_delete!

    post :restore, params: { id: @asset.id }

    assert_response :unauthorized
  end

  # ====== INDEX Ransack Filter Tests ======

  test "#index returns active assets excluding deleted by default" do
    sign_in @admin
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @admin)
    deleted.soft_delete!

    get :index

    json = response.parsed_body
    names = json["items"].map { |a| a["name"] }
    assert { names.include?("report.md") }
    assert { !names.include?("deleted.md") }
  end

  test "#index with q[deleted_at_null]=1 returns only active assets" do
    sign_in @admin
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @admin)
    deleted.soft_delete!

    get :index, params: { q: { deleted_at_null: "1" } }

    json = response.parsed_body
    names = json["items"].map { |a| a["name"] }
    assert { names.include?("report.md") }
    assert { !names.include?("deleted.md") }
  end

  test "#index with q[deleted_at_not_null]=1 returns empty when base scope excludes deleted" do
    sign_in @admin
    deleted = create(:asset, name: "deleted.md", scope: @company, created_by: @admin)
    deleted.soft_delete!

    get :index, params: { q: { deleted_at_not_null: "1" } }

    json = response.parsed_body
    names = json["items"].map { |a| a["name"] }
    assert { names.exclude?("report.md") }
    assert { names.exclude?("deleted.md") }
  end

  # ====== CREATE Source Tests ======

  test "#create auto-sets source to upload" do
    sign_in @admin

    post :create, params: {
      asset: {
        name: "new-file.txt",
        file: document_file_cache_data
      }
    }, as: :json

    assert_response :created
    asset = Asset.find_by(name: "new-file.txt")
    version = asset.versions.last
    assert { version.source == "upload" }
    assert { version.uploaded_by == @admin }
  end

  test "#create restores deleted asset with same name instead of failing" do
    sign_in @admin
    deleted = create(:asset, name: "reused.md", scope: @company, created_by: @admin)
    deleted.soft_delete!

    post :create, params: {
      asset: {
        name: "reused.md",
        file: document_file_cache_data
      }
    }, as: :json

    assert_response :created
    deleted.reload
    assert { deleted.deleted_at.nil? }
    assert { deleted.versions.count == 1 }
  end
end
