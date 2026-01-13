# frozen_string_literal: true

require "shrine"
require "image_processing/vips"

def dev_setup
  require "shrine/storage/file_system"
  Shrine.storages = {
    cache: Shrine::Storage::FileSystem.new("public", prefix: "cache"),
    store: Shrine::Storage::FileSystem.new("public", prefix: "store")
  }
  Shrine.plugin(:url_options, store: { host: "http://#{Settings.domain}" })
  Shrine.plugin(:presign_endpoint, presign: ->(id, options, request) {
    { url: Rails.application.routes.url_helpers.upload_api_v1_assets_path, fields: { key: "cache/#{id}" }, method: "POST" }
  })
end

def test_setup
  require "shrine/storage/memory"
  Shrine.logger = Logger.new("/dev/null")
  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::Memory.new
  }
  Shrine.plugin(:presign_endpoint, presign: ->(id, options, request) {
    { url: Rails.application.routes.url_helpers.upload_api_v1_assets_path, fields: { key: "cache/#{id}" }, method: "POST" }
  })
end

def other_setup
  require "shrine/storage/s3"

  s3_options = {
    access_key_id: Settings.aws.access_key_id,
    secret_access_key: Settings.aws.secret_access_key,
    bucket: Settings.aws.bucket,
    region: Settings.aws.region
  }.compact

  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: "cache", **s3_options),
    store: Shrine::Storage::S3.new(prefix: "store", **s3_options)
  }
  Shrine.plugin(:url_options, store: { expires_in: 24*60*60 })
  Shrine.plugin(:presign_endpoint, presign_options: ->(request) {
    filename = request.params["filename"]
    type     = request.params["type"]

    {
      content_disposition: ContentDisposition.inline(filename),
      content_type: type,
      content_length_range: 0..(1024 * 1024 * 1024)
    }
  })
end

def common
  Shrine.plugin(:activerecord)
  Shrine.plugin(:cached_attachment_data)
  Shrine.plugin(:restore_cached_data)
  Shrine.plugin(:pretty_location)
  Shrine.plugin(:upload_endpoint,   url: ->(uploaded_file, request) {
    options = { host: Settings.domain }
    uploaded_file.url(**options)
  })
  Shrine.plugin(:determine_mime_type, analyzer: :marcel, log_subscriber: nil)
  Shrine.plugin(:derivatives)
  Shrine.plugin(:instrumentation)
  Shrine.logger = Logger.new("/dev/null") if Rails.env.test?
end

case Rails.env.to_sym
when :development
  dev_setup && common
when :test
  test_setup && common
else
  other_setup && common
end
