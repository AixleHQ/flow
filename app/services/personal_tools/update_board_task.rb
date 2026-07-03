# frozen_string_literal: true

module PersonalTools
  class UpdateBoardTask < Base
    tool do
      display_name "Update Board Task"
      description "Update mutable fields of a board task (title, description, priority, task type, tags)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :title, type: :string, description: "Updated title."
      param :description, type: :string, description: "Updated description."
      param :priority, type: :string, description: "Updated priority."
      param :task_type, type: :string, description: "Updated task type."
      param :tags, type: :array, description: "Replacement tag list.", items: { type: "string" }
    end

    UPDATABLE = %w[title description priority task_type tags].freeze

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      updates = params.slice(*UPDATABLE).reject { |_, v| v.nil? }
      return error("No fields to update") if updates.empty?

      TaskService.update(task: task, params: updates, actor: user)
      return error("Update failed: #{task.errors.full_messages.to_sentence}") if task.errors.any?

      success(id: task.id, title: task.title, updated_fields: updates.keys)
    end
  end
end
