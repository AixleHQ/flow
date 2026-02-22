# frozen_string_literal: true

class AssetExportService
  def initialize(workflow_run_asset, project:, user:)
    @wra = workflow_run_asset
    @project = project
    @user = user
  end

  def export!(folder: nil, tags: nil, public: false)
    asset = find_or_create_asset(folder, public)
    version = create_version(asset, tags)

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

  def create_version(asset, tags)
    tempfile = download_wra_file
    begin
      version = asset.versions.create!(
        uploaded_by: @user,
        source: :workflow,
        file: tempfile,
        metadata: build_metadata(tags)
      )
      version
    ensure
      tempfile&.close
      tempfile&.unlink
    end
  end

  def download_wra_file
    return nil unless @wra.file

    tempfile = Tempfile.new(["export_", File.extname(@wra.name)])
    @wra.file.download { |tf| FileUtils.cp(tf.path, tempfile.path) }
    File.open(tempfile.path)
  rescue StandardError => e
    Rails.logger.error("[AssetExportService] Download failed: #{e.message}")
    nil
  end

  def build_metadata(tags)
    meta = {
      "provenance" => {
        "workflow_run_id" => @wra.workflow_run_id,
        "step_run_id" => @wra.produced_by_step_run_id,
        "original_name" => @wra.name,
        "exported_at" => Time.current.iso8601
      }
    }
    meta["tags"] = tags if tags.present?
    meta
  end
end
