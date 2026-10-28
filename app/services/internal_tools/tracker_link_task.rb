# frozen_string_literal: true

module InternalTools
  class TrackerLinkTask < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Link Task"
      description "Record that a board task is about an issue, so the task shows the issue and later tracker events " \
                  "find the task. Defaults to this run's task. Changes nothing in the tracker. Returns JSON: {task_id, " \
                  "task_number, tracker, issue: {id, key, url}}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      idempotent
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :task_number, type: :integer, description: "#{TASK_NUMBER_PARAM} Defaults to the task this run is about."
      param :task_id, type: :integer, description: TASK_ID_PARAM
    end

    def execute
      tracker_guard do
        task = find_task(project&.board&.board_tasks, default_id: workflow_run&.board_task_id)
        return error(task_not_found) unless task

        tracker = resolve_tracker!
        issue = tracker.tracker_provider.get_issue(tracker.external_scope_id, params[:issue])
        link_task(task, tracker, issue)
        success({ task_id: task.id, task_number: task.number, tracker: tracker.handle,
                  issue: { id: issue.id, key: issue.key, url: issue.url } }.compact.to_json)
      end
    end
  end
end
