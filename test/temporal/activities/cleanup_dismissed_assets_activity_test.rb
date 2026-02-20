# frozen_string_literal: true

require "test_helper"

class Activities::CleanupDismissedAssetsActivityTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @session = create(:terminal_session, :collected, user: @user)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
  end

  test "cleans old dismissed assets past grace period" do
    asset = create(:asset,
      name: "old-output.md",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "dismissed",
      reviewed_at: 8.days.ago
    )
    create(:asset_version, :with_file, asset: asset, uploaded_by: @user)

    activity = Activities::CleanupDismissedAssetsActivity.new

    assert_difference "Asset.count", -1 do
      result = activity.run
      assert_equal 1, result[:cleaned_count]
    end
  end

  test "leaves recently dismissed assets" do
    asset = create(:asset,
      name: "recent-dismiss.md",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "dismissed",
      reviewed_at: 2.days.ago
    )

    activity = Activities::CleanupDismissedAssetsActivity.new

    assert_no_difference "Asset.count" do
      result = activity.run
      assert_equal 0, result[:cleaned_count]
    end
  end

  test "never touches pending_review assets" do
    create(:asset,
      name: "pending.md",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "pending_review",
      reviewed_at: nil
    )

    activity = Activities::CleanupDismissedAssetsActivity.new

    assert_no_difference "Asset.count" do
      result = activity.run
      assert_equal 0, result[:cleaned_count]
    end
  end

  test "never touches active assets" do
    create(:asset,
      name: "active.md",
      scope: @company,
      created_by: @user,
      status: "active"
    )

    activity = Activities::CleanupDismissedAssetsActivity.new

    assert_no_difference "Asset.count" do
      result = activity.run
      assert_equal 0, result[:cleaned_count]
    end
  end

  test "destroys versions before destroying asset" do
    asset = create(:asset,
      name: "with-version.md",
      scope: @company,
      created_by: @user,
      terminal_session: @session,
      status: "dismissed",
      reviewed_at: 10.days.ago
    )
    create(:asset_version, :with_file, asset: asset, uploaded_by: @user)
    create(:asset_version, :with_file, asset: asset, uploaded_by: @user, version: 2)

    activity = Activities::CleanupDismissedAssetsActivity.new
    activity.run

    assert_equal 0, Asset.where(id: asset.id).count
    assert_equal 0, AssetVersion.where(asset_id: asset.id).count
  end
end
