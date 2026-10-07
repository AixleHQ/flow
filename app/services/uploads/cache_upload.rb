# frozen_string_literal: true

module Uploads
  # A slot in Shrine's :cache storage that a client PUTs bytes into directly,
  # and the URL that lets it. The bytes never pass through the application;
  # whoever hands the slot back afterwards (an asset form, an MCP tool) turns
  # it into a stored file.
  #
  # The client never chooses the object key. It is minted here, so a caller
  # cannot aim a write at another user's pending cache entry or at `store/`.
  class CacheUpload
    attr_reader :id

    def self.mint(filename:)
      new("#{SecureRandom.hex(30)}#{extension(filename)}")
    end

    # The extension is cosmetic — it makes cache objects recognisable in a
    # bucket listing and nothing reads it back. It still comes from a
    # client-supplied filename, so only a short alphanumeric suffix is allowed
    # rather than arbitrary bytes spliced into an S3 key.
    def self.extension(filename)
      extension = File.extname(filename.to_s).downcase
      extension.match?(/\A\.[a-z0-9]{1,16}\z/) ? extension : ""
    end

    def initialize(id)
      @id = id
    end

    # The object key the id lives at. Shrine's :cache storage is mounted under
    # this prefix in every environment, so one string addresses the object
    # whichever storage is behind it.
    def key = "cache/#{id}"

    # Nil where the storage cannot sign its own uploads (FileSystem and Memory,
    # locally); the caller supplies a stand-in there.
    #
    # Neither :content_type nor :content_disposition is signed. Both would
    # become SigV4 signed headers that the client must reproduce exactly, and
    # @uppy/aws-s3 v6 sends only Content-Type — so signing either turns a
    # mismatch into SignatureDoesNotMatch. Nothing is lost: cache objects are
    # never served, and Shrine::Storage::S3#upload sets content_type from the
    # marcel-derived mime type and an inline content_disposition when it
    # promotes the file to `store`, which is the copy users actually download.
    # (F32 accepted as low-risk: user assets are served from an isolated S3
    # bucket origin, not an app subdomain, so an inline HTML/SVG asset's scripts
    # run with no access to app cookies/session. Re-add a download/sandbox
    # disposition IF user assets ever move behind an app subdomain.)
    #
    # A presigned PUT has no equivalent of the POST policy's
    # :content_length_range, so no size cap is asserted here. The enforcing
    # check is each uploader's validate_max_size, which runs on promotion
    # against the bytes actually stored: an oversized upload can reach cache
    # storage but never becomes a file anyone keeps.
    def presigned_put_url
      storage.respond_to?(:presign) ? storage.presign(id, method: :put)[:url] : nil
    end

    def uploaded? = storage.exists?(id)

    private

    def storage = Shrine.storages[:cache]
  end
end
