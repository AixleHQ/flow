# frozen_string_literal: true

module Runners
  # Output and files over the 1 MiB output cap, which come back from a runner
  # through an upload to a signed URL (docs/design/agent-runtimes/DESIGN.md
  # §6.4, decision 3 of the runner design; runner/protocol/PROTOCOL.md §6.5).
  #
  #   slots   = Runners::ResultUploads.issue(%w[stdout stderr], deadline_at: deadline)   # when the op is enqueued
  #   payload = payload.merge("uploads" => Runners::ResultUploads.payload(slots))
  #   ...the runner uploads what is over the cap, and names it in its result...
  #   bytes   = Runners::ResultUploads.claim(slots, outcome_data["uploads"], "stdout")   # nil: nothing to claim
  #   Runners::ResultUploads.discard(slots)                                              # the objects it used, once the op is settled
  #
  # Who issues the URL, and when. The platform does, with the op: every `exec`
  # and `read_file` it enqueues carries one slot per output it may return
  # (`stdout` and `stderr` of an exec, `content` of a file). Signing a URL is a
  # local computation, so a slot that is never used costs nothing but its
  # (random, unguessable) key.
  #
  # Where the bytes go. Into Shrine's `cache` storage under a key the platform
  # minted (Uploads::CacheUpload), and never through the gateway or the
  # application:
  #
  # - S3: a presigned PUT URL of the bucket, the one a browser upload uses.
  # - The filesystem storage (development): the application's own stand-in for
  #   S3 (Api::V1::AssetsController#upload), a URL of the platform's main
  #   address that takes the PUT. It writes to the same `public/cache` the
  #   platform then reads from, which is the filesystem storage whose files the
  #   callback proxy's `assets` route serves (Runners::Proxy::ROUTES).
  # - The in-memory storage of the tests has no URL a process outside could
  #   call: the stand-in's URL is issued as for the filesystem, and the test's
  #   fake runner writes to the storage itself.
  #
  # Lifetime. A slot's URL is valid until the op's `deadline_at` plus
  # URL_GRACE: a runner that received the op in time may still be uploading as
  # the deadline passes. S3 enforces it; the stand-in has no expiry, and its
  # key is the capability.
  #
  # The largest upload is `Settings.runners.upload_limit`, sent in the slot as
  # `max_bytes`: a runner uploads no more than that, and the platform refuses an
  # object over it when it reads the object (TooLarge), so a runner that sent
  # more is a failed read, never a large allocation. A presigned PUT cannot carry
  # a size limit of its own.
  #
  # An upload nobody claims. The result names the uploads that hold the op's
  # output, with the key of each. The platform reads a named upload and
  # `discard`s the slots the result named once it has read them, and every slot of
  # an op that ended with no usable result, which removes the objects of an op
  # that expired after its runner had uploaded (RunnerRuntime#discard_uploads). What `discard` cannot reach, an upload that lands after it
  # (the runner got its PUT through just after the deadline), or one made by a
  # runner whose result was never posted, stays in the `cache/` prefix of the
  # storage, as an abandoned browser upload does. Nothing in the database
  # refers to it, and its key cannot be guessed. It relies on an expiry rule on
  # the bucket's `cache/` prefix, which abandoned browser uploads need as well;
  # the application declares no bucket configuration, and adds no sweep.
  module ResultUploads
    # The slot of one output.
    Slot = Data.define(:name, :upload, :url, :max_bytes) do
      def id = upload.id
    end

    # How long a URL outlives the op's deadline.
    URL_GRACE = 5.minutes
    # A URL lives at least this long, whatever the op's deadline.
    MIN_URL_LIFETIME = 60

    # Why a claimed upload could not be read.
    class Unreadable < StandardError; end

    module_function

    # The largest upload, in bytes.
    def limit
      Settings.runners.upload_limit.to_i
    end

    # One slot for each of `names`, valid until `deadline_at` and URL_GRACE.
    def issue(names, deadline_at:)
      lifetime = [ (deadline_at - Time.current).ceil + URL_GRACE.to_i, MIN_URL_LIFETIME ].max
      names.index_with do |name|
        upload = Uploads::CacheUpload.mint(filename: "")
        Slot.new(name: name, upload: upload, url: url_for(upload, lifetime), max_bytes: limit)
      end
    end

    # The slots as the `uploads` of an op's payload (PROTOCOL.md §6.5).
    def payload(slots)
      slots.transform_values { |slot| { "id" => slot.id, "url" => slot.url, "max_bytes" => slot.max_bytes } }
    end

    # The bytes of the upload the result names as `name`, or nil when it names
    # none. `reported` is the result's `data.uploads`, which is the runner's
    # word: it counts only when it names the slot's own id and the size the
    # object really has. Raises Unreadable otherwise.
    def claim(slots, reported, name)
      entry = reported.is_a?(Hash) ? reported[name] : nil
      return nil if entry.nil?

      slot = slots[name]
      raise Unreadable, "the result names an upload for #{name}, which the op had no slot for" if slot.nil?
      unless entry.is_a?(Hash) && entry["id"] == slot.id
        raise Unreadable, "the result names an upload for #{name} that is not the one issued for it"
      end

      bytes = slot.upload.read(limit: slot.max_bytes)
      if entry["size"] != bytes.bytesize
        raise Unreadable, "the upload for #{name} holds #{bytes.bytesize} bytes, and the result says #{entry['size'].inspect}"
      end

      bytes
    rescue Uploads::CacheUpload::Missing, Uploads::CacheUpload::TooLarge => e
      raise Unreadable, "the upload for #{name} cannot be read: #{e.message}"
    end

    # Removes the objects of every slot. It never raises: a storage that cannot
    # delete leaves the object to the prefix's expiry rule.
    def discard(slots)
      slots.each_value do |slot|
        slot.upload.delete
      rescue StandardError => e
        Rails.logger.warn("[Runners::ResultUploads] could not remove #{slot.upload.key}: #{e.class}: #{e.message}")
      end
    end

    def url_for(upload, lifetime)
      upload.presigned_put_url(expires_in: lifetime) ||
        Rails.application.routes.url_helpers.upload_api_v1_assets_url(
          key: upload.key, host: Settings.domain, protocol: Settings.protocol
        )
    end
    private_class_method :url_for
  end
end
