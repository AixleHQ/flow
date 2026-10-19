# frozen_string_literal: true

module Trackers
  # Copies an issue's files onto the board task linked to it
  # (docs/design/tracker-attachments.md §5, §7.2, §7.5). The tool and the copy
  # job both come through here, and meet on tracker_attachments' unique index,
  # so neither copies a file the other already did.
  #
  # Without a task nothing is kept: the files are only handed to the caller.
  class AttachmentImporter
    MAX_FILE_BYTES = 50.megabytes
    MAX_FILES = 20
    MAX_TOTAL_BYTES = 200.megabytes

    # `status` is :copied, :reused or :skipped; `reason` says why a file was skipped.
    Result = Data.define(:attachment, :status, :reason, :task_asset, :name) do
      def as_json(*)
        {
          "id" => attachment.id, "name" => name || attachment.name, "status" => status.to_s, "reason" => reason,
          "task_asset_id" => task_asset&.id
        }.compact
      end
    end

    # `throttle`, when given, is asked before each download and skips the file
    # when it answers false (Trackers::Jira::Budget).
    def initialize(project_tracker:, task:, user:, provider: nil, throttle: nil)
      @tracker = project_tracker
      @task = task
      @user = user
      @provider = provider || project_tracker.tracker_provider
      @throttle = throttle
    end

    # Copies the files `ids` names, or every file, within the limits. With a
    # block, yields each copied or reused file with where to get its bytes:
    # { url: } for a stored copy, { io: } for one kept nowhere else.
    def import(ref, ids: nil, issue_key: nil, &block)
      @issue_key = issue_key.presence
      attachments = @provider.list_attachments(@tracker.external_scope_id, ref)
      budget = { files: 0, bytes: 0 }
      taken = @task ? @task.task_assets.pluck(:name).to_set : Set.new
      results = selection(attachments, ids).map do |attachment|
        next attachment if attachment.is_a?(Result)

        import_one(ref, attachment, budget, taken, &block)
      end
      @task.board.touch if @task && results.any? { |r| r.status == :copied }
      results
    end

    private

    def selection(attachments, ids)
      return attachments if ids.nil?

      by_id = attachments.index_by { |a| a.id.to_s }
      Array(ids).map(&:to_s).uniq.map do |id|
        by_id[id] || Result.new(attachment: Attachment.new(id: id, issue_id: nil, name: nil), status: :skipped,
                                reason: "not_found", task_asset: nil, name: nil)
      end
    end

    def import_one(ref, attachment, budget, taken)
      return skip(attachment, "restricted") if attachment.restricted
      return skip(attachment, "unavailable") unless attachment.available

      copy = existing_copy(attachment)
      return reuse(attachment, copy) { |result, source| yield(result, source) if block_given? } if copy
      return skip(attachment, "over_limit") if budget[:files] >= MAX_FILES
      return skip(attachment, "too_large") if attachment.size.to_i > MAX_FILE_BYTES
      return skip(attachment, "over_limit") if budget[:bytes] + attachment.size.to_i > MAX_TOTAL_BYTES
      return skip(attachment, "rate_budget") if @throttle && !@throttle.call

      Tempfile.create([ "tracker-file", File.extname(attachment.name.to_s).first(20) ], binmode: true) do |file|
        room = [ MAX_FILE_BYTES, MAX_TOTAL_BYTES - budget[:bytes] ].min
        fetched = @provider.download_attachment(@tracker.external_scope_id, ref, attachment.id, io: file, max_bytes: room)
        file.flush
        incomplete!(attachment, file.size)
        budget[:files] += 1
        budget[:bytes] += file.size

        name = unique_name(fetched.name || attachment.name, taken)
        result = store(fetched, file, name)
        if block_given?
          # Storing the copy closes the temp file; one kept nowhere else is still open.
          file.rewind unless result.task_asset
          yield(result, result.task_asset ? { url: result.task_asset.file.url } : { io: file })
        end
        result
      end
    rescue Error => e
      skip(attachment, e.code)
    end

    def reuse(attachment, copy)
      result = Result.new(attachment: attachment, status: :reused, reason: nil, task_asset: copy, name: copy.name)
      yield(result, { url: copy.file.url })
      result
    end

    def skip(attachment, reason)
      Result.new(attachment: attachment, status: :skipped, reason: reason, task_asset: nil, name: nil)
    end

    # Jira's media redirect, followed wrongly, writes nothing and answers 200;
    # a file that came in short is not kept as if it were whole.
    def incomplete!(attachment, size)
      expected = attachment.size.to_i
      return if expected.zero? || expected == size

      raise Error.new("#{attachment.name} came in at #{size} of #{expected} bytes", code: "incomplete")
    end

    def existing_copy(attachment)
      known(attachment).find_by(external_id: attachment.id.to_s)&.task_asset
    end

    def known(attachment)
      TrackerAttachment.on_issue(project: @tracker.project, provider: @tracker.provider,
                                 instance: @provider.instance, issue_id: attachment.issue_id)
    end

    def store(attachment, file, name)
      sha = Digest::SHA256.file(file.path).hexdigest
      return Result.new(attachment: attachment, status: :copied, reason: nil, task_asset: nil, name: name) unless @task

      file.rewind
      file.define_singleton_method(:original_filename) { name }
      asset = @task.task_assets.create!(
        name: name, author: @user, author_type: :system, source: :tracker, content_sha256: sha,
        file_data: TaskAssetUploader.upload(file, :store).to_json
      )
      asset, status = record!(attachment, sha, asset)
      Result.new(attachment: attachment, status: status, reason: nil, task_asset: asset, name: asset.name)
    end

    # The copy another importer made first wins; ours is dropped.
    def record!(attachment, sha, asset)
      TrackerAttachment.create!(
        project: @tracker.project, provider: @tracker.provider, instance: @provider.instance,
        issue_id: attachment.issue_id, external_id: attachment.id.to_s, direction: :imported, content_sha256: sha,
        task_asset: asset, data: description(attachment)
      )
      [ asset, :copied ]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      row = known(attachment).find_by!(external_id: attachment.id.to_s)
      if row.task_asset.nil?
        row.update!(task_asset: asset, content_sha256: sha, data: description(attachment))
        return [ asset, :copied ]
      end

      asset.destroy!
      [ row.task_asset, :reused ]
    end

    def description(attachment)
      { "name" => attachment.name, "size" => attachment.size, "content_type" => attachment.content_type,
        "origin" => attachment.origin.to_s, "location" => attachment.location, "issue_key" => issue_key }.compact
    end

    def issue_key
      @issue_key ||= @task && ExternalResource.tracker_issues.where(board_task: @task, provider: @tracker.provider)
                                              .order(:created_at).first&.key
    end

    def unique_name(name, taken)
      clean = Workspace.clean_name(name)
      candidate = clean
      ext = File.extname(clean)
      stem = clean.delete_suffix(ext)
      counter = 1
      candidate = "#{stem}-#{counter += 1}#{ext}" while taken.include?(candidate)
      taken << candidate
      candidate
    end
  end
end
