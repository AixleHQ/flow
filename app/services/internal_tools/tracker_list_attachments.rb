# frozen_string_literal: true

module InternalTools
  class TrackerListAttachments < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: List Attachments"
      description "List the files on an issue: files attached to it, and images or files embedded in its description " \
                  "and comments. `restricted` files are visible to fewer people than the issue and are never copied; " \
                  "`available: false` files cannot be fetched through the tracker's API — open `url` in a browser " \
                  "or ask for the file. `task_asset_id` is set when this project already holds a copy. Returns JSON: " \
                  "{tracker, issue: {id, key}, attachments: [{id, name, size, content_type, origin, location, " \
                  "restricted, available, url, task_asset_id}]}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
    end

    def execute
      tracker_guard do
        tracker = resolve_tracker!
        provider = tracker.tracker_provider
        issue = provider.get_issue(tracker.external_scope_id, params[:issue])
        attachments = provider.list_attachments(tracker.external_scope_id, issue.id)
        copies = TrackerAttachment.on_issue(project: project, provider: tracker.provider, instance: provider.instance,
                                            issue_id: issue.id).where.not(task_asset_id: nil)
                                  .pluck(:external_id, :task_asset_id).to_h
        respond({
          tracker: tracker.handle, issue: { id: issue.id, key: issue.key }.compact,
          attachments: attachments.map { |a| a.as_json.merge("task_asset_id" => copies[a.id.to_s]).compact }
        })
      end
    end
  end
end
