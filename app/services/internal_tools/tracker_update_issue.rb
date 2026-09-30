# frozen_string_literal: true

module InternalTools
  class TrackerUpdateIssue < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Update Issue"
      description "Change an issue's title, description, labels or extra fields. Status and assignee have their own " \
                  "tools (tracker_transition_issue, tracker_assign_issue). Pass `expected_revision` from " \
                  "tracker_get_issue to refuse the edit if someone changed the issue meanwhile. Returns JSON: the " \
                  "updated issue plus `operation_key`."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :title, type: :string, description: "New title."
      param :description, type: :string, description: "New body."
      param :labels_add, type: :array, items: { "type" => "string" }, description: "Labels to add."
      param :labels_remove, type: :array, items: { "type" => "string" }, description: "Labels to remove."
      param :fields, type: :object, description: "Extra fields from tracker_describe's `fields`."
      param :expected_revision, type: :integer, description: "Refuse the edit unless the issue is still at this revision."
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    ATTRIBUTES = %i[title description labels_add labels_remove fields expected_revision].freeze

    def execute
      tracker_guard do
        tracker = writable_tracker!
        attributes = params.slice(*ATTRIBUTES.map(&:to_s)).to_h.symbolize_keys.compact_blank
        return error({ error: "validation_failed", message: "Nothing to update" }.to_json) if attributes.except(:expected_revision).empty?

        with_write(tracker, "update_issue", attributes.merge(issue: params[:issue]), change: { "fields" => attributes.except(:expected_revision).keys.map(&:to_s) }) do
          tracker.tracker_provider.update_issue(tracker.external_scope_id, params[:issue], attributes)
        end
      end
    end
  end
end
