# frozen_string_literal: true

module PersonalTools
  class DeleteGate < Base
    tool do
      display_name "Delete Gate"
      description "Delete a gate from a board task — how to unstick a task blocked on a CI gate " \
                  "whose resolving webhook never arrived (see list_gates for the ids)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :gate_id, type: :integer, description: "Gate id, from list_gates.", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      gate = find_gate(project)
      return error("Gate not found on this project's board") unless gate

      attributes = { deleted_gate_id: gate.id, board_task_id: gate.board_task_id, gate_type: gate.gate_type }
      gate.destroy
      success(attributes)
    end

    private

    # Scoped through this project's own board tasks — never Gate.find, which
    # would hand any company's gate over by id alone.
    def find_gate(project)
      Gate.where(board_task_id: project.board&.board_tasks&.select(:id)).find_by(id: params[:gate_id])
    end
  end
end
