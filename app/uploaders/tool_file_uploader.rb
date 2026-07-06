# frozen_string_literal: true

class ToolFileUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size 50 * 1024 * 1024
    validate_mime_type %w[
      text/plain application/json text/x-python text/x-ruby
      application/javascript text/markdown application/octet-stream
      text/x-sh application/x-sh
    ]
  end

  def generate_location(io, record: nil, name: nil, **)
    return super unless record.is_a?(ToolFile)

    basename = File.basename(record.path)
    "tool_files/#{record.tool_id}/#{basename}"
  end
end
