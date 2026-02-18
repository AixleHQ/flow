# frozen_string_literal: true

require "test_helper"

class AssetVersionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @asset = create(:asset, scope: @project, created_by: @owner)
  end

  # ====== Validations ======

  test "valid version" do
    version = build(:asset_version, asset: @asset, uploaded_by: @owner)
    assert { version.valid? }
  end

  test "version uniqueness enforced at DB level" do
    AssetVersion.create!(asset: @asset, uploaded_by: @owner)

    assert_raises(ActiveRecord::RecordNotUnique) do
      AssetVersion.connection.execute(
        "INSERT INTO asset_versions (asset_id, version, uploaded_by_id, created_at, updated_at) " \
        "VALUES (#{@asset.id}, 1, #{@owner.id}, NOW(), NOW())"
      )
    end
  end

  test "uploaded_by is required" do
    version = build(:asset_version, asset: @asset, uploaded_by: nil)
    assert { !version.valid? }
  end

  # ====== Auto-increment ======

  test "auto-increments version on create" do
    v1 = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { v1.version == 1 }

    v2 = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { v2.version == 2 }

    v3 = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { v3.version == 3 }
  end

  test "auto-increment continues after gap" do
    v1 = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { v1.version == 1 }

    v1.update!(version: 5)
    v2 = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { v2.version == 6 }
  end

  # ====== Associations ======

  test "belongs to asset" do
    version = create(:asset_version, asset: @asset, uploaded_by: @owner)
    assert { version.asset == @asset }
  end

  test "belongs to uploaded_by user" do
    version = create(:asset_version, asset: @asset, uploaded_by: @owner)
    assert { version.uploaded_by == @owner }
  end

  # ====== Source ======

  test "source defaults to upload" do
    version = AssetVersion.create!(asset: @asset, uploaded_by: @owner)
    assert { version.source == "upload" }
    assert { version.upload? }
  end

  test "source accepts workflow" do
    version = AssetVersion.create!(asset: @asset, uploaded_by: @owner, source: :workflow)
    assert { version.workflow? }
  end

  test "source accepts github" do
    version = AssetVersion.create!(asset: @asset, uploaded_by: @owner, source: :github)
    assert { version.github? }
  end

  # ====== S3 key location ======

  test "generate_location produces scoped path" do
    version = create(:asset_version, :with_file, asset: @asset, uploaded_by: @owner)
    uploader = version.file

    location = AssetFileUploader.new(:store).generate_location(
      StringIO.new("x"),
      record: version
    )

    assert { location.start_with?("project/#{@project.id}/assets/#{@asset.id}/v#{version.version}/") }
  end
end
