# frozen_string_literal: true

module Trackers
  # Puts files onto an issue, one at a time, and shows them in a comment when
  # asked to or when the tracker has no attachment list of its own
  # (docs/design/tracker-attachments.md §5.3, §7.3).
  #
  # Each file is recorded as soon as it lands, so a retry after a failed comment
  # finds it on the issue instead of uploading it again.
  class AttachmentExporter
    MAX_FILES = 10
    MAX_FILE_BYTES = 50.megabytes
    DEFAULT_COMMENT = "Files from Aixle:"

    # `status` is attached, already_on_issue or refused; `reason` says why a file was refused.
    Outcome = Data.define(:name, :status, :reason, :attachment) do
      def as_json(*)
        { "name" => name, "status" => status, "reason" => reason, "attachment" => attachment&.as_json }.compact
      end
    end

    def self.max_file_bytes = MAX_FILE_BYTES

    def initialize(project_tracker:, provider: nil, operation: nil)
      @tracker = project_tracker
      @provider = provider || project_tracker.tracker_provider
      @operation = operation
    end

    # `files` are Trackers::UploadFile. Returns a Trackers::AttachResult.
    def export(ref, files, comment: nil, force: false)
      if files.size > MAX_FILES
        raise Error.new("Send at most #{MAX_FILES} files at a time", code: "validation_failed")
      end

      issue = @provider.get_issue(scope_id, ref)
      current = @provider.list_attachments(scope_id, issue.id).index_by { |a| a.id.to_s }
      outcomes = files.map { |file| export_one(issue, file, current, force) }
      shown = outcomes.filter_map(&:attachment)
      AttachResult.new(attachments: shown, comment: post_comment(issue, comment, shown), issue_id: issue.id,
                       files: outcomes)
    end

    private

    def scope_id = @tracker.external_scope_id

    def export_one(issue, file, current, force)
      if file.size > limit
        return Outcome.new(name: file.filename, status: "refused", reason: "too_large", attachment: nil)
      end

      same = force ? nil : already_there(issue, file, current)
      return Outcome.new(name: file.filename, status: "already_on_issue", reason: nil, attachment: same) if same

      attachment = @provider.upload_attachment(scope_id, issue.id, file)
      record!(issue, file, attachment)
      Outcome.new(name: file.filename, status: "attached", reason: nil, attachment: attachment)
    rescue Error::OutcomeUnknown
      raise
    rescue Error => e
      raise if e.code == "not_authorized"

      Outcome.new(name: file.filename, status: "refused", reason: e.code, attachment: nil)
    end

    def limit
      [ self.class.max_file_bytes, @provider.max_upload_bytes ].compact.min
    end

    # Only while the tracker still lists it: a person may have deleted it since.
    def already_there(issue, file, current)
      known(issue).where(content_sha256: file.sha256).pluck(:external_id).filter_map { |id| current[id] }.first
    end

    def known(issue)
      TrackerAttachment.on_issue(project: @tracker.project, provider: @tracker.provider, instance: @provider.instance,
                                 issue_id: issue.id)
    end

    def record!(issue, file, attachment)
      TrackerAttachment.create!(
        project: @tracker.project, provider: @tracker.provider, instance: @provider.instance, issue_id: issue.id,
        external_id: attachment.id.to_s, direction: :exported, content_sha256: file.sha256,
        tracker_operation_id: @operation&.id,
        data: { "name" => attachment.name, "size" => file.size, "content_type" => file.content_type,
                "issue_key" => issue.key }.compact
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def post_comment(issue, comment, shown)
      return if shown.empty?

      text = comment.presence || (@provider.attachment_list? ? nil : DEFAULT_COMMENT)
      return unless text

      @provider.add_comment(scope_id, issue.id, @provider.compose_comment(text, shown))
    end
  end
end
