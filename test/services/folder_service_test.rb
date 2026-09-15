# frozen_string_literal: true

require "test_helper"

class FolderServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @service = FolderService.new(scope: @project, actor: @owner)
  end

  # ====== create! ======

  test "create! makes a root folder" do
    folder = @service.create!("dashboard")
    assert { folder.persisted? }
    assert { folder.path == "dashboard" }
    assert { folder.scope == @project }
    assert { folder.created_by == @owner }
  end

  test "create! makes a nested folder when its parent already exists as a persisted folder" do
    @service.create!("dashboard")
    folder = @service.create!("dashboard/specs")
    assert { folder.path == "dashboard/specs" }
  end

  test "create! makes a nested folder when its parent exists only via an asset" do
    create(:asset, folder: "dashboard", scope: @project, created_by: @owner)
    folder = @service.create!("dashboard/specs")
    assert { folder.path == "dashboard/specs" }
  end

  test "create! rejects a bad path format" do
    assert_raises(FolderService::InvalidPathError) { @service.create!("bad name") }
    assert_raises(FolderService::InvalidPathError) { @service.create!("a//b") }
  end

  test "create! rejects a nested path whose parent does not exist" do
    assert_raises(FolderService::InvalidPathError) { @service.create!("dashboard/specs") }
  end

  test "create! rejects a name colliding with an existing sibling folder" do
    @service.create!("dashboard")
    assert_raises(FolderService::CollisionError) { @service.create!("dashboard") }
  end

  test "create! rejects a name colliding with an existing sibling file" do
    create(:asset, name: "dashboard", folder: nil, scope: @project, created_by: @owner)
    assert_raises(FolderService::CollisionError) { @service.create!("dashboard") }
  end

  test "create! sees the parent company's folders and assets as existing parents" do
    company_folder = FolderService.new(scope: @company, actor: @owner)
    company_folder.create!("shared")
    folder = @service.create!("shared/notes")
    assert { folder.path == "shared/notes" }
    assert { folder.scope == @project }
  end

  # ====== relocate! (rename) ======

  test "relocate! renames a folder and cascades to descendant folders and assets" do
    @service.create!("dashboard")
    @service.create!("dashboard/specs")
    asset = create(:asset, name: "api.md", folder: "dashboard/specs", scope: @project, created_by: @owner)

    travel_to 1.hour.from_now do
      @service.relocate!(from_path: "dashboard", to_path: "dash")
    end

    assert { Folder.for_project(@project).pluck(:path).sort == %w[dash dash/specs] }
    assert { asset.reload.folder == "dash/specs" }
  end

  test "relocate! bumps updated_at on the cascaded rows" do
    @service.create!("dashboard")
    asset = create(:asset, name: "api.md", folder: "dashboard", scope: @project, created_by: @owner)
    original_folder_updated_at = Folder.for_project(@project).find_by(path: "dashboard").updated_at
    original_asset_updated_at = asset.updated_at

    travel_to 1.hour.from_now do
      @service.relocate!(from_path: "dashboard", to_path: "dash")
    end

    assert { Folder.for_project(@project).find_by(path: "dash").updated_at > original_folder_updated_at }
    assert { asset.reload.updated_at > original_asset_updated_at }
  end

  test "relocate! is a no-op when the destination equals the source" do
    @service.create!("dashboard")
    result = @service.relocate!(from_path: "dashboard", to_path: "dashboard")
    assert { result == { from: "dashboard", to: "dashboard" } }
    assert { Folder.for_project(@project).pluck(:path) == [ "dashboard" ] }
  end

  test "relocate! rejects a destination name already used by a sibling" do
    @service.create!("dashboard")
    @service.create!("archive")
    assert_raises(FolderService::CollisionError) { @service.relocate!(from_path: "dashboard", to_path: "archive") }
  end

  test "relocate! leaves company assets untouched and blocks when a company asset is nested inside a project folder" do
    @service.create!("initiate")
    create(:asset, name: "kickoff.md", folder: "initiate", scope: @company, created_by: @owner)

    assert_raises(FolderService::CollisionError) { @service.relocate!(from_path: "initiate", to_path: "kickoff") }
  end

  # ====== relocate! (move) ======

  test "relocate! moves a folder under a different parent, cascading its subtree" do
    @service.create!("dashboard")
    @service.create!("dashboard/specs")
    @service.create!("archive")
    asset = create(:asset, name: "api.md", folder: "dashboard/specs", scope: @project, created_by: @owner)

    @service.relocate!(from_path: "dashboard/specs", to_path: "archive/specs")

    assert { Folder.for_project(@project).pluck(:path).sort == %w[archive archive/specs dashboard] }
    assert { asset.reload.folder == "archive/specs" }
  end

  test "relocate! rejects moving a folder into one of its own subfolders" do
    @service.create!("dashboard")
    @service.create!("dashboard/specs")

    assert_raises(FolderService::InvalidPathError) do
      @service.relocate!(from_path: "dashboard", to_path: "dashboard/specs/nested")
    end
  end

  test "relocate! raises RecordNotFound when the source path doesn't exist in this scope" do
    assert_raises(ActiveRecord::RecordNotFound) { @service.relocate!(from_path: "ghost", to_path: "renamed") }
  end

  test "relocate! rejects a destination whose parent does not exist" do
    @service.create!("dashboard")
    assert_raises(FolderService::InvalidPathError) { @service.relocate!(from_path: "dashboard", to_path: "ghost/dashboard") }
  end

  test "relocate! moving a folder whose subtree has multiple nested files preserves their relative structure" do
    @service.create!("a")
    @service.create!("a/x")
    @service.create!("a/y")
    file_x = create(:asset, name: "file.md", folder: "a/x", scope: @project, created_by: @owner)
    file_y = create(:asset, name: "file.md", folder: "a/y", scope: @project, created_by: @owner)
    @service.create!("b")

    @service.relocate!(from_path: "a", to_path: "b/a")

    assert { file_x.reload.folder == "b/a/x" }
    assert { file_y.reload.folder == "b/a/y" }
    assert { Folder.for_project(@project).pluck(:path).sort == %w[b b/a b/a/x b/a/y] }
  end

  # ====== destroy! ======

  test "destroy! removes an empty folder" do
    @service.create!("dashboard")
    @service.destroy!(path: "dashboard")
    assert { Folder.for_project(@project).count.zero? }
  end

  test "destroy! raises NotEmptyError with the direct item count for a non-empty folder" do
    @service.create!("dashboard")
    @service.create!("dashboard/specs")
    create(:asset, name: "a.md", folder: "dashboard", scope: @project, created_by: @owner)

    error = assert_raises(FolderService::NotEmptyError) { @service.destroy!(path: "dashboard") }
    assert { error.item_count == 2 }
    assert { Folder.for_project(@project).exists?(path: "dashboard") }
  end

  test "destroy! raises RecordNotFound for a folder that doesn't exist (or is only derived)" do
    create(:asset, folder: "derived", scope: @project, created_by: @owner)
    assert_raises(ActiveRecord::RecordNotFound) { @service.destroy!(path: "derived") }
  end

  test "destroy! with recursive: true soft-deletes descendant assets and removes descendant folders" do
    @service.create!("dashboard")
    @service.create!("dashboard/specs")
    asset = create(:asset, name: "a.md", folder: "dashboard", scope: @project, created_by: @owner)
    nested_asset = create(:asset, name: "b.md", folder: "dashboard/specs", scope: @project, created_by: @owner)

    result = @service.destroy!(path: "dashboard", recursive: true)

    assert { result[:deleted_assets] == 2 }
    assert { result[:deleted_folders] == 2 }
    assert { asset.reload.deleted_at.present? }
    assert { nested_asset.reload.deleted_at.present? }
    assert { Folder.for_project(@project).count.zero? }
  end

  test "destroy! with recursive: true is blocked in project scope when a company asset is nested" do
    @service.create!("dashboard")
    create(:asset, name: "kickoff.md", folder: "dashboard", scope: @company, created_by: @owner)

    assert_raises(FolderService::CollisionError) { @service.destroy!(path: "dashboard", recursive: true) }
    assert { Folder.for_project(@project).exists?(path: "dashboard") }
  end
end
