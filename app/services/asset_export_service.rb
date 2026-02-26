# frozen_string_literal: true

class AssetExportService
  def initialize(workflow_run_asset, project:, user:)
    @wra = workflow_run_asset
    @project = project
    @user = user
  end

  def export!(folder: nil, public: false)
    asset = find_or_create_asset(folder, public)
    version = create_version(asset)

    Rails.logger.info("[AssetExportService] Exported #{@wra.name} → Asset##{asset.id} v#{version.version}")
    { asset: asset, version: version }
  end

  private

  def find_or_create_asset(folder, is_public)
    existing = Asset.find_by(
      scope_type: "Project",
      scope_id: @project.id,
      name: @wra.name,
      folder: folder
    )

    if existing
      existing.update!(status: "active") if existing.deleted?
      existing
    else
      Asset.create!(
        scope_type: "Project",
        scope_id: @project.id,
        name: @wra.name,
        folder: folder,
        status: "active",
        created_by: @user,
        public: is_public
      )
    end
  end

  def create_version(asset)
    tempfile = download_wra_file
    return nil unless tempfile

    begin
      version = asset.versions.build(
        uploaded_by: @user,
        source: :workflow
      )
      version.file = tempfile
      version.save!
      version
    ensure
      tempfile.close!
    end
  end

  def download_wra_file
    return nil unless @wra.file

    @wra.file.download
  end

end
