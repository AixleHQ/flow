# frozen_string_literal: true

class TaskAssetUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
    validate_mime_type %w[
      image/jpeg image/png image/gif image/webp image/svg+xml
      application/pdf text/plain text/csv text/markdown
      application/zip application/json application/octet-stream
    ]
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(TaskAsset)

    task_id = record.board_task_id
    filename = super(io).split("/").last
    "task_assets/#{task_id}/#{filename}"
  end
end
