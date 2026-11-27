# frozen_string_literal: true

module InternalTools
  class TrackerTransitionIssue < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Transition Issue"
      description "Move an issue to another status — on the tracker's board, another column. The status must be one " \
                  "the issue's type allows (tracker_describe lists them); the error names the allowed ones. Returns " \
                  "JSON: the updated issue plus `operation_key`."
      tags :tracker
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :status, type: :string, description: "Target status name.", required: true
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    def execute
      tracker_guard do
        tracker = writable_tracker!
        with_write(tracker, "transition_issue", { issue: params[:issue], status: params[:status] },
                   change: { "field" => "status", "to" => params[:status] }) do
          tracker.tracker_provider.transition_issue(tracker.external_scope_id, params[:issue], params[:status])
        end
      end
    end
  end
end
