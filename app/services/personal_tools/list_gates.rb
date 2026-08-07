# frozen_string_literal: true

module PersonalTools
  class ListGates < Base
    tool do
      display_name "List Gates"
      description "List the gates on a board task — what a task reported as `pending_gates` " \
                  "actually is. Gates are CI gates (GitHub checks/workflow, GitLab pipeline) " \
                  "created and resolved by incoming CI webhooks, so there is deliberately no " \
                  "tool to create or resolve one by hand; use delete_gate to clear a gate whose " \
                  "webhook never arrived."
      audience :user
      tags :board
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project.board, :show?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      rows = task.gates.includes(:creator).order(:created_at).map do |gate|
        { id: gate.id, gate_type: gate.gate_type, status: gate.status, metadata: gate.metadata,
          creator: gate.creator&.name, creator_id: gate.creator_id,
          created_at: gate.created_at, resolved_at: gate.resolved_at }
      end
      success(task_id: task.id, gates: rows)
    end
  end
end
