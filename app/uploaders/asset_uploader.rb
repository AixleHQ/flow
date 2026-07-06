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

  Attacher.validate do
    validate_max_size 100 * 1024 * 1024
    validate_mime_type %w[
      image/jpeg image/png image/gif image/webp image/svg+xml
      application/pdf text/plain text/csv
      application/zip application/json
    ]
  end
end
