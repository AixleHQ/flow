# frozen_string_literal: true

class AssetFileUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(AssetVersion)

    asset = record.asset
    scope_type = asset.scope_type.downcase
    scope_id = asset.scope_id
    version = record.version || "draft"
    filename = super(io).split("/").last

    "#{scope_type}/#{scope_id}/assets/#{asset.id}/v#{version}/#{filename}"
  end
end
