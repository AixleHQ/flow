# frozen_string_literal: true

require "aws-sdk-s3"

namespace :s3 do
  desc "Upload file to the main S3 bucket"
  task upload: :environment do
    s3_client = Shrine.storages[:store].client
    bucket_key = ENV.fetch("BUCKET_KEY", nil)
    file_path = ENV.fetch("FILE", nil)

    response = s3_client.put_object(
      bucket: Settings.aws.bucket,
      key: bucket_key,
      body: File.read(file_path)
    )

    pp response.to_h
  end

  desc "Download file from the main S3 bucket"
  task download: :environment do
    s3_client = Shrine.storages[:store].client
    key = ENV.fetch("BUCKET_KEY", nil)
    file_name = File.basename(key)

    response = s3_client.get_object(bucket: Settings.aws.bucket, key:)
    pp response.to_h

    File.write(file_name, response.body.read)
  end

  desc "Delete file from the main S3 bucket"
  task delete: :environment do
    s3_client = Shrine.storages[:store].client
    key = ENV.fetch("BUCKET_KEY", nil)

    response = s3_client.delete_object(bucket: Settings.aws.bucket, key:)
    pp response.to_h
  end
end
