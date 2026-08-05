# frozen_string_literal: true

module PersonalTools
  class UpdateBoardTask < Base
    tool do
      display_name "Update Board Task"
      description "Update mutable fields of a board task (title, description, priority, task type, tags, assignee)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :title, type: :string, description: "Updated title."
      param :description, type: :string, description: "Updated description."
      param :priority, type: :string, description: "Updated priority."
      param :task_type, type: :string, description: "Updated task type."
      param :tags, type: :array, description: "Replacement tag list.", items: { type: "string" }
      param :assignee_id, type: :integer,
            description: "User id to assign the task to — must be a project member (see list_project_members)."
      param :unassign, type: :boolean, description: "Clear the current assignee. Cannot be combined with assignee_id."
    end

    UPDATABLE = %w[title description priority task_type tags].freeze

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = project.board&.board_tasks&.find_by(id: params[:task_id])
      return error("Task not found on this project's board") unless task

      updates = params.slice(*UPDATABLE).reject { |_, v| v.nil? }
      if assign? && unassign?
        return error("Pass either assignee_id or unassign, not both")
      elsif assign? || unassign?
        updates["assignee_id"] = unassign? ? nil : params[:assignee_id]
      end
      return error("No fields to update") if updates.empty?

      TaskService.update(task: task, params: updates, actor: user)
      # The model rejects an assignee who can't reach the project, so a bad
      # assignee_id surfaces as a tool error rather than a silent no-op.
      return error("Update failed: #{task.errors.full_messages.to_sentence}") if task.errors.any?

      success(id: task.id, title: task.title, assignee_id: task.assignee_id, updated_fields: updates.keys)
    end

    private

    def assign? = params[:assignee_id].present?
    def unassign? = ActiveModel::Type::Boolean.new.cast(params[:unassign]).present?
  end
end
