# frozen_string_literal: true

module InternalTools
  class TrackerListUsers < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: List Users"
      description "Find the people an issue in a tracker's project can be assigned to, by name or email. Pass a " \
                  "returned `id` as tracker_assign_issue's assignee when a name is ambiguous. Returns JSON: " \
                  "{tracker, users: [{id, name}]}. Not every tracker can list users."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :query, type: :string, description: "Part of a name or an email.", required: true
    end

    def execute
      tracker_guard do
        tracker = resolve_tracker!
        users = tracker.tracker_provider.list_users(tracker.external_scope_id, query: params[:query].to_s)
        respond({ tracker: tracker.handle, users: users })
      end
    end
  end
end
