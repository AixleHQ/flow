# frozen_string_literal: true

module InternalTools
  class TrackerCreateIssue < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Create Issue"
      description "File a new issue. `type` must be one of the tracker's issue types (tracker_describe lists them). " \
                  "When this run is about a board task, the new issue is linked to it unless `link_to_task` is false. " \
                  "Returns JSON: the created issue plus `operation_key`."
      tags :tracker
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :type, type: :string, description: "Issue type, e.g. Bug or Task.", required: true
      param :title, type: :string, description: "Issue title.", required: true
      param :description, type: :string, description: "Issue body."
      param :assignee, type: :string, description: "Assignee, as the tracker names users."
      param :labels, type: :array, items: { "type" => "string" }, description: "Labels to set."
      param :fields, type: :object, description: "Extra fields from tracker_describe's `fields`, e.g. {\"priority\": 2}."
      param :link_to_task, type: :boolean, description: "Link the issue to this run's board task. Default true."
      param :operation_key, type: :string, description: Concerns::TrackerContext::OPERATION_KEY_PARAM
    end

    ATTRIBUTES = %i[type title description assignee labels fields].freeze

    def execute
      tracker_guard do
        tracker = writable_tracker!(ref: nil)
        attributes = params.slice(*ATTRIBUTES.map(&:to_s)).to_h.symbolize_keys.compact_blank
        issue = nil
        result = with_write(tracker, "create_issue", attributes) do
          issue = tracker.tracker_provider.create_issue(tracker.external_scope_id, attributes)
        end
        link_run_task(tracker, issue) if issue && params[:link_to_task] != false
        result
      end
    end
  end
end
