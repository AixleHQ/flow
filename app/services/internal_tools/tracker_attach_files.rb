# frozen_string_literal: true

module InternalTools
  class TrackerAttachFiles < Base
    include Concerns::TrackerContext
    include Concerns::TrackerFiles

    FILE_ITEM = {
      "type" => "object",
      "properties" => {
        "content" => { "type" => "string", "description" => "Inline text; needs filename." },
        "file_path" => { "type" => "string", "description" => "A path in your container." },
        "asset_id" => { "type" => "integer", "description" => "A project asset." },
        "task_asset_id" => { "type" => "integer", "description" => "An attachment of a board task in this project." },
        "filename" => { "type" => "string", "description" => "The name the file gets on the issue." }
      }
    }.freeze

    tool do
      display_name "Tracker: Attach Files"
      description "Put files onto an issue. Each `files` entry sets EXACTLY ONE source: `content` (inline text, needs " \
                  "`filename`), `file_path` (a path in your container), `asset_id` (a project asset) or " \
                  "`task_asset_id` (a board task's attachment). Up to #{Trackers::AttachmentExporter::MAX_FILES} files " \
                  "of #{Trackers::AttachmentExporter::MAX_FILE_BYTES / 1.megabyte} MB. With `comment`, a comment is " \
                  "posted that shows the files; trackers that keep no attachment list (Linear, GitHub) always get one. " \
                  "A file whose bytes are already on the issue is not sent again unless `force` is true. A file put on " \
                  "an issue cannot be taken back by Aixle: never send secrets. Returns JSON: {attachments, comment, " \
                  "issue_id, files: [{name, status, reason}], operation_key}; status is attached, already_on_issue or " \
                  "refused."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :files, type: :array, items: FILE_ITEM, description: "The files to put on the issue.", required: true
      param :comment, type: :string, description: "Optional comment text shown above the files."
      param :force, type: :boolean, description: "Send files even when the same bytes are already on the issue."
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    def execute
      tracker_guard do
        tracker = writable_tracker!
        with_upload_files(max_bytes: Trackers::AttachmentExporter.max_file_bytes) do |files, err|
          next err if err
          next error("Pass at least one file") if files.empty?

          payload = { issue: params[:issue], comment: params[:comment].presence, force: params[:force] == true,
                      files: files.map { |f| { name: f.filename, sha256: f.sha256 } } }.compact
          with_write(tracker, "attach_files", payload) do |operation|
            Trackers::AttachmentExporter.new(project_tracker: tracker, operation: operation, task: workflow_run&.board_task,
                                             user: workflow_run&.user || session&.user)
                                        .export(params[:issue], files, comment: params[:comment], force: params[:force] == true)
          end
        end
      end
    end
  end
end
