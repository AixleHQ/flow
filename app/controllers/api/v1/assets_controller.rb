# frozen_string_literal: true

module Api
  module V1
    class AssetsController < ApplicationController
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
        id = cache_id
        render json: { method: "PUT", url: presigned_put_url(id), key: cache_key(id) }
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

      def cache_id
        "#{SecureRandom.hex(30)}#{sanitized_extension}"
      end

      # The object key an id lives at. Shrine's :cache storage is mounted under this prefix in
      # every environment — S3 in production, FileSystem in development, Memory in test, where
      # #upload stands in for S3 and takes the prefixed key in its path — so one string addresses
      # the object whichever storage is behind it. Kept next to CACHE_KEY_PATTERN, which is the
      # same prefix spelled as a guard.
      def cache_key(id)
        "cache/#{id}"
      end

      # The extension is cosmetic — it makes cache objects recognisable in a bucket listing and
      # nothing reads it back. It still comes from a client-supplied filename, so allow only a
      # short alphanumeric suffix rather than splicing arbitrary bytes into an S3 key.
      def sanitized_extension
        extension = File.extname(params[:filename].to_s).downcase
        extension.match?(/\A\.[a-z0-9]{1,16}\z/) ? extension : ""
      end

      # The client never chooses the object key. @uppy/aws-s3 v6 generates a key of its own and
      # passes it to `signRequest`, but we ignore it and sign the one minted here, then tell the
      # plugin which key we actually signed for — so a caller cannot aim a write at another
      # user's pending cache entry or at `store/`, and the id it reports back is ours.
      def presigned_put_url(id)
        # S3 signs its own uploads; the FileSystem/Memory storages used locally cannot, so
        # #upload stands in for S3 there. It has to be an absolute URL: the plugin derives the
        # uploadURL by feeding this string to `new URL(...)` with no base, which throws on a
        # path-relative one.
        return upload_api_v1_assets_url(key: cache_key(id)) unless cache_storage.respond_to?(:presign)

        # Neither :content_type nor :content_disposition is signed here. Both would become
        # SigV4 signed headers that the browser must reproduce exactly, and v6 sends only
        # Content-Type — so signing either turns a mismatch into SignatureDoesNotMatch.
        # Nothing is lost: cache objects are never served (the frontend hands the id straight
        # back to us), and Shrine::Storage::S3#upload sets content_type from the marcel-derived
        # mime type and an inline content_disposition when it promotes the file to `store`,
        # which is the copy users actually download. (F32 accepted as low-risk: user assets are
        # served from an isolated S3 bucket origin, not an app subdomain, so an inline HTML/SVG
        # asset's scripts run with no access to app cookies/session. Re-add a download/sandbox
        # disposition IF user assets ever move behind an app subdomain.)
        #
        # A presigned PUT also has no equivalent of the POST policy's :content_length_range, so
        # the 1 GB cap is no longer asserted at presign time. The enforcing check is unchanged:
        # AssetFileUploader's validate_max_size runs on promotion against the bytes actually
        # stored, so an oversized upload can reach cache storage but never becomes an asset.
        cache_storage.presign(id, method: :put)[:url]
      end

      def cache_storage
        Shrine.storages[:cache]
      end
    end
  end
end
