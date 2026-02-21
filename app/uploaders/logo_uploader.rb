# frozen_string_literal: true

class LogoUploader < Shrine
  include ImageProcessing::Vips

  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :derivatives
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data

  # Attacher.validate do
  #   validate_max_size 5*1024*1024, message: "is too large (max is 5 MB)"
  #   validate_mime_type %w[image/jpeg image/png image/svg+xml]
  # end
end
