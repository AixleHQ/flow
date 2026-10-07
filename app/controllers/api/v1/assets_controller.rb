# frozen_string_literal: true

module Api
  module V1
    class AssetsController < ApplicationController
      # The dev/test S3 stand-in: @uppy/aws-s3 PUTs the bytes with no CSRF header,
      # exactly as it would to S3. The key it writes to was minted by #presign.
      skip_before_action :verify_authenticity_token, only: :upload
      # An id minted by #presign, optionally carrying the original file's extension. The dev/test
      # upload endpoint accepts nothing else, so a caller cannot steer a write out of `cache/`.
      CACHE_KEY_PATTERN = %r{\Acache/\h{60}(\.[a-z0-9]{1,16})?\z}

      # @summary Generate a presigned URL for direct file upload
      #
      # `key` is the object key this URL was signed for, and it is what the browser hands back
      # once the bytes are stored. @uppy/aws-s3 6.1 honours a `key` alongside `url` in a
      # signRequest answer — it uses that key for the rest of the upload and reports it to
      # `upload-success` — so the frontend reads the cache id straight off the response instead
      # of recovering it by splitting the upload URL on "/cache/".
      def presign
        upload = Uploads::CacheUpload.mint(filename: params[:filename])
        render json: { method: "PUT", url: presigned_put_url(upload), key: upload.key }
      end

      # @summary Upload a file to temporary cache storage (development/test only)
      def upload
        # Belt and braces: this action writes client bytes straight into storage, so it stays
        # unreachable outside dev/test regardless of how :cache happens to be configured.
        return head :not_found unless Rails.env.local?

        key = request.path_parameters[:key].to_s
        return head :bad_request unless CACHE_KEY_PATTERN.match?(key)

        cache_storage.upload(request.body, key.delete_prefix("cache/"))
        head :no_content
      end

      private

      # S3 signs its own uploads; the FileSystem/Memory storages used locally cannot, so #upload
      # stands in for S3 there. It has to be an absolute URL: @uppy/aws-s3 derives the uploadURL
      # by feeding this string to `new URL(...)` with no base, which throws on a path-relative one.
      def presigned_put_url(upload)
        upload.presigned_put_url || upload_api_v1_assets_url(key: upload.key)
      end

      def cache_storage
        Shrine.storages[:cache]
      end
    end
  end
end
