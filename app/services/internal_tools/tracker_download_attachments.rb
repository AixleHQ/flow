# frozen_string_literal: true

module InternalTools
  class TrackerDownloadAttachments < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Download Attachments"
      description "Put an issue's files in your workspace, under /workspace/tracker/<issue key>/, and keep a copy on " \
                  "the board task linked to the issue. Without attachment_ids, every file is fetched, up to " \
                  "#{Trackers::AttachmentImporter::MAX_FILES} files and " \
                  "#{Trackers::AttachmentImporter::MAX_TOTAL_BYTES / 1.megabyte} MB; files over " \
                  "#{Trackers::AttachmentImporter::MAX_FILE_BYTES / 1.megabyte} MB and restricted files are skipped. " \
                  "A file already copied is taken from the copy. Changes nothing in the tracker. Returns JSON: " \
                  "{tracker, issue: {id, key}, task_id, files: [{id, name, path, status, reason, task_asset_id}]}; " \
                  "status is copied, reused or skipped."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      idempotent
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :attachment_ids, type: :array, items: { "type" => "string" },
                             description: "Ids from tracker_list_attachments. Default: every file."
    end

    def execute
      tracker_guard do
        tracker = resolve_tracker!
        provider = tracker.tracker_provider
        issue = provider.get_issue(tracker.external_scope_id, params[:issue])
        task = issue_task(tracker, issue)
        workspace = Trackers::Workspace.for_session(session)
        paths = {}
        importer = Trackers::AttachmentImporter.new(project_tracker: tracker, task: task, user: workflow_run&.user || session&.user,
                                                    provider: provider)
        ids = params[:attachment_ids].presence
        results = importer.import(issue.id, ids: ids, issue_key: issue.key) do |result, source|
          path = Trackers::Workspace.path_for(issue.key || issue.id, result.name)
          placed = path && workspace && (source[:url] ? workspace.fetch(source[:url], path) : workspace.write(path, source[:io].read))
          paths[result.attachment.id] = path if placed
        end
        respond({
          tracker: tracker.handle, issue: { id: issue.id, key: issue.key }.compact, task_id: task&.id,
          files: results.map { |r| r.as_json.merge("path" => paths[r.attachment.id]).compact },
          note: note(task, workspace)
        }.compact)
      end
    end

    private

    def note(task, workspace)
      return "No container is running, so nothing was placed in a workspace." unless workspace
      return if task

      "No board task is linked to this issue, so no copy was kept. Link one with tracker_link_task to keep them."
    end
  end
end
