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

    ActiveRecord::Base.transaction do
      @task.lock!
      new_pos = @position || (@target_column.board_tasks.maximum(:position).to_i + 1)
      @task.update!(board_column: @target_column, position: new_pos)
      compact_positions(from_column) if from_column.id != @target_column.id
    end

    ColumnTransition.create!(
      board_task: @task,
      from_column: from_column,
      to_column: @target_column,
      actor: @actor,
      actor_type: @actor_type
    )

    broadcast_move
    @task.reload
  end

  private

  def compact_positions(column)
    column.board_tasks.order(:position).each_with_index do |t, idx|
      t.update_column(:position, idx + 1) if t.position != idx + 1
    end
  end

  def broadcast_move
    BoardChannel.broadcast_event(
      @task.board_column.board,
      "task_moved",
      BoardTaskSerializer.new(@task).as_json,
      actor_id: @actor.id
    )
  rescue StandardError => e
    Rails.logger.warn("[TaskMoveService#broadcast_move] #{e.message}")
  end
end
