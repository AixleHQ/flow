# frozen_string_literal: true

class ToolFileUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data

  def generate_location(io, record: nil, name: nil, **)
    return super unless record.is_a?(ToolFile)

    basename = File.basename(record.path)
    "tool_files/#{record.tool_id}/#{basename}"
  end
end
