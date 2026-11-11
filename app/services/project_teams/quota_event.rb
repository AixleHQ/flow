# frozen_string_literal: true

module ProjectTeams
  # `workflow_run.quota_exceeded`: a run stopped on its owner's agent quota. An
  # event trigger can listen for it — to notify someone, or to hand work to
  # another member — instead of polling runs.
  module QuotaEvent
    EVENT_TYPE = "#{TriggerBinding::RUN_EVENT_PREFIX}quota_exceeded".freeze

    module_function

    def publish(run, credential)
      # A run this very event started that hits a quota again would fire it
      # again, and again; its cooldown alone would not end that loop.
      return if started_by_quota_event?(run)

      TriggerEngine.publish(
        event_type: EVENT_TYPE, source: TriggerBinding::RUN_EVENT_SOURCE, subject: run.id,
        project: run.project, board_task: run.board_task, dedup_key: "#{EVENT_TYPE}:#{run.id}",
        data: {
          "workflow_run_id" => run.id, "workflow_id" => run.workflow_id, "board_task_id" => run.board_task_id,
          "user_id" => run.user_id, "team_id" => run.team_id, "agent_type" => credential&.agent_type,
          "quota_exhausted_until" => credential&.reload&.quota_exhausted_until&.iso8601,
          "trigger_binding_id" => TriggerDispatch.where(workflow_run_id: run.id).pick(:trigger_binding_id)
        }.compact
      )
    rescue StandardError => e
      Rails.logger.warn("[ProjectTeams::QuotaEvent] not published for run ##{run.id}: #{e.message}")
      nil
    end

    def started_by_quota_event?(run)
      TriggerDispatch.joins(:trigger_event)
                     .where(workflow_run_id: run.id, trigger_events: { event_type: EVENT_TYPE }).exists?
    end
  end
end
