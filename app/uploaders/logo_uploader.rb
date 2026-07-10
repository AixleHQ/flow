# frozen_string_literal: true

class LogoUploader < Shrine
  include ImageProcessing::Vips

  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :derivatives
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  # MIME is determined from the actual bytes (marcel), not the client-sent
  # Content-Type, so a mislabelled upload is rejected. See also F32: the presign
  # path must force a download disposition for the SVG case.
  Attacher.validate do
    validate_max_size 5 * 1024 * 1024, message: "is too large (max is 5 MB)"
    validate_mime_type %w[image/jpeg image/png image/gif image/webp image/svg+xml]
  end
end
