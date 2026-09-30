# frozen_string_literal: true

module InternalTools
  class TrackerLinkTask < Base
    include Concerns::TrackerContext

    tool do
      display_name "Tracker: Link Task"
      description "Record that a board task is about an issue, so the task shows the issue and later tracker events " \
                  "find the task. Defaults to this run's task. Changes nothing in the tracker. Returns JSON: {task_id, " \
                  "tracker, issue: {id, key, url}}."
      tags :tracker
      inject_when :tracker_run
      requires_integration :tracker
      unavailable_message "No task tracker is connected to this project. Add one on the project's Trackers page."
      idempotent
      param :tracker, type: :string, description: Concerns::TrackerContext::TRACKER_PARAM
      param :issue, type: :string, description: Concerns::TrackerContext::ISSUE_PARAM, required: true
      param :task_id, type: :integer, description: "Board task id. Defaults to the task this run is about."
    end

    def execute
      tracker_guard do
        task = params[:task_id].present? ? project_task(params[:task_id]) : workflow_run&.board_task
        return error("No board task: pass task_id, or run this from a task-scoped workflow") unless task

        tracker = resolve_tracker!
        issue = tracker.tracker_provider.get_issue(tracker.external_scope_id, params[:issue])
        link_task(task, tracker, issue)
        success({ task_id: task.id, tracker: tracker.handle, issue: { id: issue.id, key: issue.key, url: issue.url } }.compact.to_json)
      end
    end

    private

    def project_task(id)
      BoardTask.joins(:board).find_by(id: id, boards: { project_id: project&.id })
    end
  end
end
