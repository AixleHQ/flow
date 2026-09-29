# frozen_string_literal: true

class TaskAssetUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers
  plugin :rack_response

  # General-purpose user attachments (docs, office files, video, …) — no MIME
  # allowlist. Assets are opened from the isolated S3 bucket origin; a shared one
  # is served on the app origin only by the public viewer's raw endpoint, under
  # `Content-Security-Policy: sandbox`. Either way type is not an XSS vector here.
  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(TaskAsset)

    task_id = record.board_task_id
    filename = super(io).split("/").last
    "task_assets/#{task_id}/#{filename}"
  end
end
