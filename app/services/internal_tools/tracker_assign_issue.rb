# frozen_string_literal: true

module InternalTools
  class TrackerAssignIssue < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Assign Issue"
      description "Set an issue's assignee, as the tracker names users (for Azure Boards: an email or display " \
                  "name). Returns JSON: the updated issue plus `operation_key`."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :assignee, type: :string, description: "Who to assign.", required: true
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    def execute
      tracker_guard do
        tracker = writable_tracker!
        with_write(tracker, "assign_issue", { issue: params[:issue], assignee: params[:assignee] },
                   change: { "field" => "assignee", "to" => params[:assignee] }) do
          tracker.tracker_provider.assign_issue(tracker.external_scope_id, params[:issue], params[:assignee])
        end
      end
    end
  end
end
