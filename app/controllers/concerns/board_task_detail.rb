# frozen_string_literal: true

# One task's detail — the board's drawer (`?n=`) and the task's own page render the
# same component, so both ship the same props under the same names: the component
# partially reloads them by name.
module BoardTaskDetail
  extend ActiveSupport::Concern

  # Epics offered as a parent in the create-task drawer. Nesting is one level deep and
  # boards run to a handful of epics, so the whole list ships; the cap only exists so a
  # pathological board cannot unbound the payload.
  EPIC_OPTIONS_LIMIT = 200

  private

  # task_assets is included so TaskDetailResource.assets_count avoids an N+1, and
  # parent_task so TaskDetailResource.parent_task_title fires no extra query. Archived
  # tasks are found too: a link to a task outlives its place on the board.
  def find_board_task(board, number)
    board.board_tasks
         .includes(:assignee, :assignee_team, :parent_task, :child_tasks, :task_comments, :task_assets, :workflow_runs, :gates)
         .find_by(number: number)
  end

  # What the task's pickers choose from: its column, parent epic, tags and assignee.
  def board_options_props(board)
    {
      columns: -> {
        board.board_columns.with_tasks_count.includes(column_workflow_binding: :workflow)
             .order(:position).map { |c| BoardColumnResource.new(c).to_h }
      },
      board_tags: -> { board.board_tasks.active.distinct.pluck(Arel.sql("unnest(tags)")).compact.sort },
      epics: -> {
        board.board_tasks.active.where(task_type: "epic").order(:title).limit(EPIC_OPTIONS_LIMIT)
             .pluck(:id, :number, :title).map { |id, number, title| { id: id, number: number, title: title } }
      },
      members: -> { current_project.joined_member_users.map { |u| BoardMemberResource.new(u).to_h } },
      # docs/design/project-teams.md: a task can be assigned to a team instead of a person.
      teams: -> { current_project.project_teams.map { |team| { id: team.id, name: team.name } } }
    }
  end

  def task_detail_props(task)
    {
      task_cable_stream: -> { task ? inertia_cable_stream(task) : nil },
      selected_task: -> { task ? TaskDetailResource.new(task).to_h : nil },
      task_comments: -> {
        next [] unless task
        task.task_comments.includes(:author).order(created_at: :desc)
            .map { |c| TaskCommentResource.new(c).to_h }
      },
      task_assets: -> {
        next [] unless task
        task.task_assets.includes(:tracker_attachment).order(created_at: :desc).map { |a| TaskAssetResource.new(a).to_h }
      },
      task_activities: -> {
        next [] unless task
        task.board_activities.includes(:actor, :board_task).order(created_at: :desc)
            .map { |a| BoardActivityResource.new(a).to_h }
      },
      task_workflow_runs: -> {
        next [] unless task
        # The resource renders a row per step run, timed by its session; without the
        # preload a task with a run history costs queries per step run.
        task.workflow_runs.with_total_cost_cents.includes(:workflow, :runner, :user, :team, step_runs: %i[step terminal_session])
            .order(created_at: :desc)
            .map { |r| TaskWorkflowRunResource.new(r).to_h }
      },
      task_statistics: -> {
        next nil unless task
        TaskStatisticsResource.new(TaskStatisticsService.new(task: task).call).to_h
      }
    }
  end
end
