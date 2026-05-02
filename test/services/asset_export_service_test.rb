# frozen_string_literal: true

require "test_helper"

class AssetExportServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @run = create(:workflow_run, project: @project, user: @user)
    @wra = create(:workflow_run_asset, workflow_run: @run, name: "report.md")
    WorkflowRunAsset.any_instance.stubs(:file).returns(nil)
  end

  test "creates new active asset when no matching asset exists" do
    service = AssetExportService.new(@wra, project: @project, user: @user)
    result = service.export!(folder: nil)

    asset = result[:asset]
    assert asset.persisted?
    assert_equal "active", asset.status
    assert_nil asset.deleted_at
    assert_equal "Project", asset.scope_type
    assert_equal @project.id, asset.scope_id
  end

  test "promoted asset appears in accessible_from_project scope" do
    service = AssetExportService.new(@wra, project: @project, user: @user)
    result = service.export!(folder: nil)

    assert Asset.accessible_from_project(@project).include?(result[:asset])
  end

  test "restores soft-deleted asset and marks it active on promotion" do
    deleted_asset = create(:asset, scope: @project, created_by: @user, name: "report.md", status: "active")
    deleted_asset.soft_delete!
    assert deleted_asset.deleted?

    service = AssetExportService.new(@wra, project: @project, user: @user)
    result = service.export!(folder: nil)

    assert_equal deleted_asset.id, result[:asset].id
    deleted_asset.reload
    assert_equal "active", deleted_asset.status
    assert_nil deleted_asset.deleted_at
  end

  test "restored soft-deleted asset appears in accessible_from_project scope" do
    deleted_asset = create(:asset, scope: @project, created_by: @user, name: "report.md", status: "active")
    deleted_asset.soft_delete!

    service = AssetExportService.new(@wra, project: @project, user: @user)
    service.export!(folder: nil)

    assert Asset.accessible_from_project(@project).include?(deleted_asset.reload)
  end

  test "activates pending_review asset on promotion" do
    pending_asset = create(:asset, scope: @project, created_by: @user,
                           name: "report.md", status: "pending_review")

    service = AssetExportService.new(@wra, project: @project, user: @user)
    result = service.export!(folder: nil)

    assert_equal pending_asset.id, result[:asset].id
    assert_equal "active", pending_asset.reload.status
    assert Asset.accessible_from_project(@project).include?(pending_asset.reload)
  end

  test "returns existing active asset without modification" do
    active_asset = create(:asset, scope: @project, created_by: @user, name: "report.md", status: "active")

    service = AssetExportService.new(@wra, project: @project, user: @user)
    result = service.export!(folder: nil)

    assert_equal active_asset.id, result[:asset].id
    assert_equal "active", active_asset.reload.status
  end
end
