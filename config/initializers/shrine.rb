# frozen_string_literal: true

require "shrine"
require "content_disposition"
require "image_processing/vips"

# Direct browser uploads are presigned by Api::V1::AssetsController#presign, which signs the
# :cache storage itself rather than mounting Shrine's presign_endpoint/upload_endpoint Rack
# apps — neither was ever mounted, and neither fits @uppy/aws-s3 v6's raw-PUT protocol.
module ShrineSetup
  module_function

  def configure!(env)
    case env.to_sym
    when :development then file_system!
    when :test then memory!
    else s3!
    end
    common_plugins!
  end

  def file_system!
    require "shrine/storage/file_system"
    Shrine.storages = {
      cache: Shrine::Storage::FileSystem.new("public", prefix: "cache"),
      store: Shrine::Storage::FileSystem.new("public", prefix: "store")
    }
    Shrine.plugin(:url_options, store: { host: "#{Settings.protocol}://#{Settings.domain}" })
  end

  def memory!
    require "shrine/storage/memory"
    Shrine.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
  end

  def s3!
    require "shrine/storage/s3"
    options = {
      access_key_id: Settings.aws.access_key_id,
      secret_access_key: Settings.aws.secret_access_key,
      bucket: Settings.aws.bucket,
      region: Settings.aws.region
    }.compact
    Shrine.storages = {
      cache: Shrine::Storage::S3.new(prefix: "cache", **options),
      store: Shrine::Storage::S3.new(prefix: "store", **options)
    }
    Shrine.plugin(:url_options, store: { expires_in: 24 * 60 * 60 })
  end

  def common_plugins!
    Shrine.plugin(:activerecord)
    Shrine.plugin(:cached_attachment_data)
    Shrine.plugin(:restore_cached_data)
    Shrine.plugin(:pretty_location)
    Shrine.plugin(:determine_mime_type, analyzer: :marcel, log_subscriber: nil)
    Shrine.plugin(:derivatives)
    Shrine.plugin(:instrumentation)
    Shrine.logger = Logger.new(File::NULL) if Rails.env.test?
  end
end

ShrineSetup.configure!(Rails.env)
