# frozen_string_literal: true

require "test_helper"

class AssetBulkServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @service = AssetBulkService.new(scope: @project, actor: @owner)
  end

  test "move updates the folder for every id and reports it as succeeded" do
    a = create(:asset, folder: nil, scope: @project, created_by: @owner)
    b = create(:asset, folder: "old", scope: @project, created_by: @owner)

    result = @service.call(action: "move", asset_ids: [ a.id, b.id ], folder: "new")

    assert { result[:succeeded].sort == [ a.id, b.id ].sort }
    assert { result[:skipped].empty? }
    assert { a.reload.folder == "new" }
    assert { b.reload.folder == "new" }
  end

  test "move to root clears the folder when given a blank value" do
    a = create(:asset, folder: "docs", scope: @project, created_by: @owner)

    result = @service.call(action: "move", asset_ids: [ a.id ], folder: nil)

    assert { result[:succeeded] == [ a.id ] }
    assert_nil a.reload.folder
  end

  test "move skips (does not raise) a row whose destination collides with an existing name" do
    create(:asset, name: "readme.md", folder: "dest", scope: @project, created_by: @owner)
    moving = create(:asset, name: "readme.md", folder: "src", scope: @project, created_by: @owner)

    result = @service.call(action: "move", asset_ids: [ moving.id ], folder: "dest")

    assert { result[:succeeded].empty? }
    assert { result[:skipped].first[:id] == moving.id }
    assert { result[:skipped].first[:reason].present? }
    assert { moving.reload.folder == "src" }
  end

  test "delete soft-deletes every id and reports it as succeeded" do
    a = create(:asset, scope: @project, created_by: @owner)
    b = create(:asset, scope: @project, created_by: @owner)

    result = @service.call(action: "delete", asset_ids: [ a.id, b.id ])

    assert { result[:succeeded].sort == [ a.id, b.id ].sort }
    assert { a.reload.deleted? }
    assert { b.reload.deleted? }
  end

  test "an id outside this scope's own assets is reported skipped with reason Not found" do
    company_asset = create(:asset, scope: @company, created_by: @owner)

    result = @service.call(action: "move", asset_ids: [ company_asset.id ], folder: "x")

    assert { result[:succeeded].empty? }
    assert { result[:skipped] == [ { id: company_asset.id, reason: "Not found" } ] }
    assert_nil company_asset.reload.folder
  end

  test "a mix of valid and invalid ids partitions correctly, one bad row does not fail the batch" do
    ok = create(:asset, folder: nil, scope: @project, created_by: @owner)
    missing_id = ok.id + 1_000_000

    result = @service.call(action: "move", asset_ids: [ ok.id, missing_id ], folder: "docs")

    assert { result[:succeeded] == [ ok.id ] }
    assert { result[:skipped] == [ { id: missing_id, reason: "Not found" } ] }
  end

  test "raises for an unknown action" do
    asset = create(:asset, scope: @project, created_by: @owner)
    assert_raises(ArgumentError) { @service.call(action: "obliterate", asset_ids: [ asset.id ]) }
  end
end
