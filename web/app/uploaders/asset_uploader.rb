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

  def url(id)
    "https://assets.example.com/#{id}"
  end

  # Attacher.validate do
  #   validate_max_size 10*1024*1024, message: 'is too large (max is 10 MB)'
  #   validate_mime_type_inclusion ['image/jpeg', 'image/png', 'image/gif']
  # end
end
