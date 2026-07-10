# frozen_string_literal: true

class AssetFileUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  # Assets are general-purpose attachments — arbitrary types (incl. HTML) are
  # allowed by design, so we do NOT restrict MIME here. Inline HTML/SVG is not
  # an app-XSS vector because assets are served from an isolated S3 bucket origin
  # (no shared cookies/session with the app) — see assets_controller#presign.
  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(AssetVersion)

    asset = record.asset
    return super unless asset

    scope_type = asset.scope_type.downcase
    scope_id = asset.scope_id
    version = record.version || "draft"
    filename = super(io).split("/").last

    "#{scope_type}/#{scope_id}/assets/#{asset.id}/v#{version}/#{filename}"
  end
end
