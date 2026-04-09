# frozen_string_literal: true

class TaskService
  class << self
    def create(board:, params:, actor:)
      task = board.board_tasks.build(params)

      if task.save
        record_activity(board, :task_created, actor, task: task,
          metadata: { title: task.title, task_type: task.task_type })
        check_auto_trigger(task: task, column: task.board_column, actor: actor)
      end

      task
    end

    def update(task:, params:, actor:)
      task.assign_attributes(params)
      changes = task.changes

      if task.save
        record_activity(task.board, :task_updated, actor, task: task,
          metadata: { changes: changes.except("updated_at") })
      end

      task
    end

    def destroy(task:, actor:)
      title = task.title
      board = task.board

      if task.destroy
        record_activity(board, :task_deleted, actor, metadata: { title: title })
      end

      task
    end

    def move(task:, to_column:, position: nil, actor:, actor_type: :human)
      from_column = task.board_column
      column_changed = from_column.id != to_column.id

      ActiveRecord::Base.transaction do
        task.lock!

        if position
          if column_changed
            insert_at_position(to_column, task, position)
          else
            reorder_within_column(to_column, task, task.position, position)
          end
        end

        new_pos = position || (to_column.board_tasks.maximum(:position).to_i + 1)
        task.update!(board_column: to_column, position: new_pos)
      end

      if column_changed
        ColumnTransition.create!(
          board_task: task, from_column: from_column, to_column: to_column,
          actor: actor, actor_type: actor_type
        )
        record_activity(task.board, :task_moved, actor, task: task,
          metadata: { from_column: from_column.name, to_column: to_column.name })
        check_auto_trigger(task: task, column: to_column, actor: actor)
      end

      task.reload
    end

    def add_comment(task:, params:, actor:)
      comment = task.task_comments.build(params)
      comment.author = actor
      comment.author_type = :human

      if comment.save
        record_activity(task.board, :comment_added, actor, task: task,
          metadata: { tag: comment.tags&.first, preview: comment.body.to_s.truncate(100) })
      end

      comment
    end

    def add_asset(task:, params:, actor:)
      asset = task.task_assets.build(params)
      asset.author = actor
      asset.author_type = :human

      if asset.save
        record_activity(task.board, :asset_attached, actor, task: task,
          metadata: { name: asset.name, content_type: asset.file&.metadata&.dig("mime_type") })
      end

      asset
    end

    def destroy_asset(task:, asset:, actor:)
      asset.destroy
    end

    def trigger_workflow(task:, binding:, actor:)
      unless [ :manual, :auto ].include?(binding&.trigger_mode&.to_sym)
        return { error: "No workflow binding on current column" }
      end

      if task.workflow_runs.where(state: %w[pending running paused]).exists?
        return { error: "Active workflow run already exists for this task" }
      end

      WorkflowService.start(
        workflow: binding.workflow,
        project: task.board.project,
        user: actor,
        task: task,
        mode: :non_interactive
      )
    end

    def resolve_wait(wait:, resolution_data: {})
      wait.update!(
        status: :resolved,
        resolved_at: Time.current,
        resolution_data: resolution_data
      )

      task = wait.board_task
      check_auto_trigger(task: task, column: task.board_column, actor: wait.creator)
    end

    def remove_wait(wait:, actor:)
      task = wait.board_task
      column = task.board_column

      wait.destroy!
      check_auto_trigger(task: task, column: column, actor: actor)
    end

    def check_auto_trigger(task:, column:, actor:)
      binding = column.column_workflow_binding
      return unless binding&.trigger_mode&.to_sym == :auto
      return if task.task_waits.pending.exists?
      return if task.workflow_runs.where(state: %w[pending running paused]).exists?

      WorkflowService.start(
        workflow: binding.workflow,
        project: column.board.project,
        user: actor,
        task: task,
        mode: :non_interactive
      )
    rescue StandardError => e
      Rails.logger.error("[TaskService] Auto-trigger failed: #{e.message}")
    end

    private

    def record_activity(board, event_type, actor, task: nil, metadata: {})
      BoardActivity.create!(
        board: board, board_task: task, event_type: event_type,
        actor: actor, actor_type: :human, metadata: metadata
      )
      board.touch
    rescue StandardError => e
      Rails.logger.warn("[TaskService] Failed to record activity #{event_type}: #{e.message}")
    end

    def insert_at_position(target_column, task, position)
      target_column.board_tasks
        .where.not(id: task.id)
        .where("position >= ?", position)
        .update_all("position = position + 1")
    end

    def reorder_within_column(target_column, task, old_pos, new_pos)
      if old_pos < new_pos
        target_column.board_tasks
          .where.not(id: task.id)
          .where("position > ? AND position <= ?", old_pos, new_pos)
          .update_all("position = position - 1")
      elsif old_pos > new_pos
        target_column.board_tasks
          .where.not(id: task.id)
          .where("position >= ? AND position < ?", new_pos, old_pos)
          .update_all("position = position + 1")
      end
    end
  end
end
