# frozen_string_literal: true

class TaskMoveService
  def initialize(task:, target_column:, actor:, position: nil, actor_type: :human)
    @task = task
    @target_column = target_column
    @actor = actor
    @position = position
    @actor_type = actor_type
  end

  def execute
    from_column = @task.board_column
    column_changed = from_column.id != @target_column.id

    ActiveRecord::Base.transaction do
      @task.lock!

      if @position
        if column_changed
          insert_at_position
        else
          reorder_within_column
        end
      end

      new_pos = @position || (@target_column.board_tasks.maximum(:position).to_i + 1)
      @task.update!(board_column: @target_column, position: new_pos)
    end

    if column_changed
      ColumnTransition.create!(
        board_task: @task, from_column: from_column, to_column: @target_column,
        actor: @actor, actor_type: @actor_type
      )
      WorkflowAutoTriggerService.check!(task: @task, column: @target_column, actor: @actor, actor_type: @actor_type)
    end

    @task.reload
  end

  private

  def insert_at_position
    @target_column.board_tasks
      .where.not(id: @task.id)
      .where("position >= ?", @position)
      .update_all("position = position + 1")
  end

  def reorder_within_column
    old_pos = @task.position
    new_pos = @position

    if old_pos < new_pos
      @target_column.board_tasks
        .where.not(id: @task.id)
        .where("position > ? AND position <= ?", old_pos, new_pos)
        .update_all("position = position - 1")
    elsif old_pos > new_pos
      @target_column.board_tasks
        .where.not(id: @task.id)
        .where("position >= ? AND position < ?", new_pos, old_pos)
        .update_all("position = position + 1")
    end
  end
end
