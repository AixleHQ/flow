# frozen_string_literal: true

class SessionLogUploader < Shrine
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
    return super unless record.is_a?(SessionLog)

    session_id = record.terminal_session_id
    filename = super(io).split("/").last

    "sessions/#{session_id}/logs/#{filename}"
  end
end
