# frozen_string_literal: true

module PersonalTools
  class UpdateBoardTask < Base
    tool do
      display_name "Update Board Task"
      description "Update mutable fields of a board task (title, description, priority, task type, tags, assignee)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
      param :title, type: :string, description: "Updated title."
      param :description, type: :string, description: "Updated description."
      param :priority, type: :string, description: "Updated priority."
      param :task_type, type: :string, description: "Updated task type."
      param :tags, type: :array, description: "Replacement tag list.", items: { type: "string" }
      param :assignee_id, type: :integer,
            description: "User id to assign the task to — must be a project member (see list_project_members)."
      param :assignee_team_id, type: :integer,
            description: "Team id to assign the task to (see list_project_teams): each run of the task goes to the " \
                         "member the team's strategy picks. Replaces a person assignee."
      param :unassign, type: :boolean,
            description: "Clear the current assignee, person or team. Cannot be combined with assignee_id or assignee_team_id."
    end

    UPDATABLE = %w[title description priority task_type tags].freeze

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::TasksPolicy, project: project)
      task = find_task(project.board&.board_tasks)
      return error(task_not_found) unless task

      updates = params.slice(*UPDATABLE).reject { |_, v| v.nil? }
      return error("Pass one of assignee_id, assignee_team_id or unassign") if [ assign?, assign_team?, unassign? ].count(true) > 1

      if unassign?
        updates.merge!("assignee_id" => nil, "assignee_team_id" => nil)
      elsif assign?
        updates["assignee_id"] = params[:assignee_id]
      elsif assign_team?
        updates["assignee_team_id"] = params[:assignee_team_id]
      end
      return error("No fields to update") if updates.empty?

      TaskService.update(task: task, params: updates, actor: user)
      # The model rejects an assignee who can't reach the project, so a bad
      # assignee_id surfaces as a tool error rather than a silent no-op.
      return error("Update failed: #{task.errors.full_messages.to_sentence}") if task.errors.any?

      success(id: task.id, number: task.number, title: task.title, assignee_id: task.assignee_id,
              assignee_team_id: task.assignee_team_id, updated_fields: updates.keys)
    end

    private

    def assign? = params[:assignee_id].present?
    def assign_team? = params[:assignee_team_id].present?
    def unassign? = ActiveModel::Type::Boolean.new.cast(params[:unassign]).present?
  end
end
