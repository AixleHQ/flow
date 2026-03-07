# frozen_string_literal: true

class BoardContextResolver
  def self.resolve(session)
    if session.step_run&.workflow_run&.board_task_id.present?
      return session.step_run.workflow_run.board_task.board
    end

    session.project&.board
  end
end
