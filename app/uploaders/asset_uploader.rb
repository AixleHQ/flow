class AssetUploader < Shrine
  include ImageProcessing::Vips
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :derivatives
  plugin :rack_response
  plugin :instrumentation
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  def url(id)
    "https://assets.example.com/#{id}"
  end

  # General-purpose assets — no MIME allowlist (served only from the isolated S3
  # bucket origin, never rendered on the app origin).
  Attacher.validate do
    validate_max_size 100 * 1024 * 1024
  end
end
