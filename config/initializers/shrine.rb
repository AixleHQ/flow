# frozen_string_literal: true

require "shrine"
require "content_disposition"
require "image_processing/vips"

# Direct browser uploads are presigned by Api::V1::AssetsController#presign, which signs the
# :cache storage itself rather than mounting Shrine's presign_endpoint/upload_endpoint Rack
# apps — neither was ever mounted, and neither fits @uppy/aws-s3 v6's raw-PUT protocol.

def dev_setup
  require "shrine/storage/file_system"
  Shrine.storages = {
    cache: Shrine::Storage::FileSystem.new("public", prefix: "cache"),
    store: Shrine::Storage::FileSystem.new("public", prefix: "store")
  }
  Shrine.plugin(:url_options, store: { host: "#{Settings.protocol}://#{Settings.domain}" })
end

def test_setup
  require "shrine/storage/memory"
  Shrine.logger = Logger.new("/dev/null")
  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::Memory.new
  }
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
end

def common
  Shrine.plugin(:activerecord)
  Shrine.plugin(:cached_attachment_data)
  Shrine.plugin(:restore_cached_data)
  Shrine.plugin(:pretty_location)
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
