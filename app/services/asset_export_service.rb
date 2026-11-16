# frozen_string_literal: true

class AssetExportService
  # A file the running session has written to its outputs. It becomes a
  # WorkflowRunAsset only when the session ends, so a step that promotes its
  # own output exports the bytes it reads from the container.
  LiveOutput = Data.define(:name, :content) do
    def file = self

    def download
      Tempfile.new([ "asset_export_", File.extname(name) ]).tap do |tempfile|
        tempfile.binmode
        tempfile.write(content)
        tempfile.rewind
      end
    end
  end

  # source: a WorkflowRunAsset or a LiveOutput.
  def initialize(source, project:, user:)
    @source = source
    @project = project
    @user = user
  end

  def export!(folder: nil, public: false)
    asset = find_or_create_asset(folder, public)
    version = create_version(asset)

    Rails.logger.info("[AssetExportService] Exported #{@source.name} → Asset##{asset.id} v#{version&.version}")
    { asset: asset, version: version }
  end

  private

  def find_or_create_asset(folder, is_public)
    folder = Asset.normalize_folder(folder)
    existing = Asset.find_by(
      scope_type: "Project",
      scope_id: @project.id,
      name: @source.name,
      folder: folder
    )

    if existing
      existing.update!(status: "active", deleted_at: nil) if existing.deleted? || existing.status != "active"
      existing
    else
      Asset.create!(
        scope_type: "Project",
        scope_id: @project.id,
        name: @source.name,
        folder: folder,
        status: "active",
        created_by: @user,
        public: is_public
      )
    end
  end

  def create_version(asset)
    tempfile = download_source_file
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

  def download_source_file
    return nil unless @source.file

    @source.file.download
  end
end
