# frozen_string_literal: true

module InternalTools
  class TrackerAddComment < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Add Comment"
      description "Post a comment on an issue. Returns JSON: {id, issue_id, body, created_at, operation_key}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :body, type: :string, description: "Comment text.", required: true
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    def execute
      tracker_guard do
        tracker = writable_tracker!
        with_write(tracker, "add_comment", { issue: params[:issue], body: params[:body] }) do
          tracker.tracker_provider.add_comment(tracker.external_scope_id, params[:issue], params[:body])
        end
      end
    end
  end
end
