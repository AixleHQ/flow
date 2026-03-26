# frozen_string_literal: true

# Shared filtering logic for analytics services that support restricting
# sessions to those belonging to workflow runs whose board task matches
# the given tags and/or task_type criteria.
module TaskFilterable
  private

  def filtered_board_tasks
    board_tasks = project.board&.board_tasks || BoardTask.none
    board_tasks = board_tasks.tags_overlap(tags) if tags.present?
    board_tasks = board_tasks.where(task_type:) if task_type.present?
    board_tasks
  end

  def apply_task_filters(sessions)
    return sessions unless tags.present? || task_type.present?

    sessions.where(
      id: StepRun.where(workflow_run_id: WorkflowRun.where(board_task_id: filtered_board_tasks.select(:id))).select(:terminal_session_id)
    )
  end
end
