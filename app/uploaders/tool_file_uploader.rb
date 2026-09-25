# frozen_string_literal: true

class ToolFileUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  # Tool files are arbitrary code/config the tool author uploads — no MIME
  # allowlist (marcel sniffs .js as text/javascript, .html as text/html, etc.,
  # which a narrow list wrongly rejected). Not rendered on the app origin.
  Attacher.validate do
    validate_max_size 50 * 1024 * 1024
  end

  # Unique per upload: tool + basename alone would make /workspace/a/config.json and
  # /workspace/b/config.json one object, the later upload overwriting the other.
  def generate_location(io, record: nil, name: nil, **)
    return super unless record.is_a?(ToolFile)

    "tool_files/#{record.tool_id}/#{generate_uid(io)}/#{File.basename(record.path)}"
  end
end
