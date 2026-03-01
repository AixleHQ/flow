# frozen_string_literal: true

class ActivityRecorder
  class << self
    def record(board:, event_type:, actor:, actor_type:, task: nil, metadata: {})
      activity = BoardActivity.create!(
        board: board,
        board_task: task,
        event_type: event_type,
        actor: actor,
        actor_type: actor_type,
        metadata: metadata
      )

      BoardChannel.broadcast_event(
        board, "activity_created",
        { id: activity.id, event_type: event_type, task_id: task&.id },
        actor_id: actor.id
      )

      activity
    rescue StandardError => e
      Rails.logger.warn("[ActivityRecorder] Failed to record #{event_type}: #{e.message}")
      nil
    end
  end
end
