# frozen_string_literal: true

module InternalTools
  class TrackerGetIssue < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Get Issue"
      description "Read one issue in full: title, description, type, status, assignees, labels, revision and " \
                  "tracker-specific fields. Returns JSON: {tracker, issue}."
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
        respond({ tracker: tracker.handle, issue: tracker.tracker_provider.get_issue(tracker.external_scope_id, params[:issue]) })
      end
    end
  end
end
