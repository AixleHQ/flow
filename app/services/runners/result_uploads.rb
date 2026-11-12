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
  # application, by a presigned PUT URL of the bucket (S3), the one a browser
  # upload uses.
  #
  # Known limitation: uploads need a storage that presigns. With one that cannot
  # (the filesystem storage of development, the in-memory one of the tests) the
  # platform issues no slots (`available?` is false): the runner then returns what
  # fits the 1 MiB cap, as it did before uploads, and the cleanup's
  # `log-collection-report.txt` says which files were not collected whole and why
  # (RunnerRuntime#read_file_result).
  #
  # Lifetime. A slot's URL is valid until the op's `deadline_at` plus
  # URL_GRACE, which is only a margin for clocks that differ: there is one
  # deadline. The runner never uploads past `deadline_at` and the platform
  # settles the op there, so an op that carries slots is given a `budget` on top
  # of the time it needs itself.
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

    # The slowest upload the budget allows for, in bytes per second (8 Mbit/s).
    MIN_UPLOAD_RATE = 1.megabyte
    # What an op with slots is given beyond the upload itself, in seconds: the
    # runner's last request, and its result being posted.
    RESULT_MARGIN = 30

    # How long a URL outlives the op's deadline: a margin, not a second deadline.
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

    # Whether the platform can issue a slot at all: its storage signs uploads.
    def available?
      Shrine.storages[:cache].respond_to?(:presign)
    end

    # The seconds an op with slots is given for the upload of an output of the
    # largest size, at MIN_UPLOAD_RATE, plus RESULT_MARGIN: 32 MiB takes 32 s at
    # 1 MiB/s, so 62 s on top of the op's own time.
    def budget
      (limit.to_f / MIN_UPLOAD_RATE).ceil + RESULT_MARGIN
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
        raise(ArgumentError, "the cache storage cannot sign an upload; check Runners::ResultUploads.available? first")
    end
    private_class_method :url_for
  end
end
