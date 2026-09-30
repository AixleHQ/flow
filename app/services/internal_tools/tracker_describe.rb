# frozen_string_literal: true

module InternalTools
  class TrackerDescribe < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Describe"
      description "Describe a tracker's process: its statuses (with a portable category: todo, in_progress, done, " \
                  "canceled), issue types with their statuses and required fields, and the extra fields that can be " \
                  "set. Call it before creating or transitioning issues. Returns JSON: {statuses, issue_types, " \
                  "fields, supports}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      read_only
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
    end

    def execute
      tracker_guard do
        tracker = resolve_tracker!(ref: nil)
        respond(tracker.tracker_provider.describe(tracker.external_scope_id).merge(tracker: tracker.handle))
      end
    end
  end
end
