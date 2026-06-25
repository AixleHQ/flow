# frozen_string_literal: true

class WorkflowService
  class << self
    def update(workflow:, params:)
      attrs = params.to_h
      if (incoming_config = attrs.delete("config")).present?
        workflow.merge_config!(incoming_config)
      end
      attrs.any? ? workflow.update(attrs) : workflow.errors.none?
    rescue ActiveRecord::RecordInvalid
      false
    end

    def start(workflow:, project:, user:, task: nil, mode: :interactive, overrides: {}, input_asset_ids: [], repository_ids: [], agent_runtime: nil, requested_model: nil, shared_context: {})
      run = project.workflow_runs.new(
        workflow: workflow,
        user: user,
        board_task_id: task&.id,
        mode: mode,
        step_overrides: overrides,
        input_asset_ids: input_asset_ids,
        repository_ids: repository_ids,
        agent_runtime: agent_runtime.presence,
        shared_context: { "requested_model" => requested_model.presence }.compact.merge(shared_context.to_h.stringify_keys)
      )

      validate_mode!(run, workflow, overrides)
      return run if run.errors.any?

      return run unless run.save

      workflow.steps.not_deleted.order(:position).each do |step|
        run.step_runs.find_or_create_by!(step: step)
      end

      TemporalWorkflowRegistry.start_workflow_execution(run)
      record_activity(run, :workflow_started)
      broadcast_task_updated(run)

      run
    rescue StandardError => e
      Rails.logger.error("[WorkflowService] Failed to start workflow for run ##{run&.id}: #{e.message}")
      run
    end

    def cancel(run:)
      send_signal(run, "workflow_cancelled")
      cancel_active_step_runs(run)
      run.cancel! if run.may_cancel?
      record_activity(run, :workflow_cancelled)
      broadcast_task_updated(run)
    end

    def complete(run:)
      run.complete! if run.may_complete?
      record_activity(run, :workflow_completed)
      notify_slack(run, "✅ Workflow *#{run.workflow.name}* finished.")
      broadcast_task_updated(run)
    end

    def fail(run:)
      run.fail! if run.may_fail?
      record_activity(run, :workflow_failed)
      notify_slack(run, "❌ Workflow *#{run.workflow.name}* failed.")
      broadcast_task_updated(run)
    end

    def approve_step(step_run:)
      step_run.mark_completed!
      send_signal(step_run.workflow_run, "step_completed", step_run.id)
    end

    def retry_step(step_run:)
      new_step_run = step_run.workflow_run.step_runs.create!(
        step: step_run.step,
        state: :pending
      )
      send_signal(step_run.workflow_run, "step_retried",
                  { "old_step_run_id" => step_run.id, "new_step_run_id" => new_step_run.id })
    end

    def skip_step(step_run:, reason: nil)
      step_run.mark_skipped!(reason || "Skipped by user")
      send_signal(step_run.workflow_run, "step_skipped", step_run.id)
    end

    def notify_container_finished(step_run:)
      execution_id = workflow_execution_id(step_run.workflow_run)
      TemporalService.send_signal(execution_id, :container_finished, step_run.id)
    rescue StandardError => e
      Rails.logger.error("[WorkflowService] Failed to signal container_finished for step_run ##{step_run.id}: #{e.message}")
    end

    private

    def workflow_execution_id(run)
      "workflow-execution-#{run.id}"
    end

    def send_signal(run, signal_name, payload = nil)
      TemporalService.send_signal(workflow_execution_id(run), signal_name, payload)
    rescue StandardError => e
      Rails.logger.error("[WorkflowService] Failed to send signal #{signal_name} for run ##{run.id}: #{e.message}")
    end

    def validate_mode!(run, workflow, overrides)
      return unless run.non_interactive?

      blocking_steps = workflow.steps.not_deleted.reject do |step|
        override = overrides[step.id.to_s]
        override ? override["auto_run"] : step.allow_non_interactive
      end

      return if blocking_steps.empty?

      names = blocking_steps.map(&:name)
      run.errors.add(:mode, "Cannot run fully automatic: steps #{names.join(', ')} require user interaction")
    end

    def cancel_active_step_runs(run)
      run.step_runs.where(state: %w[pending running waiting_input]).find_each do |sr|
        SessionService.cancel(session: sr.terminal_session) if sr.terminal_session
        sr.mark_cancelled!
      rescue StandardError => e
        Rails.logger.warn("[WorkflowService] Failed to cancel step_run ##{sr.id}: #{e.message}")
      end
    end

    def broadcast_task_updated(run)
      return unless run.board_task_id.present?

      run.board_task.board.touch
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Failed to broadcast task update for run ##{run.id}: #{e.message}")
    end

    # Best-effort safety-net reply to the originating Slack thread (no-op for
    # non-Slack runs). The agent-driven slack_post_message tool is the primary path.
    def notify_slack(run, text)
      Slack::Notifier.notify_run(run, text)
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Slack notify failed for run ##{run.id}: #{e.message}")
    end

    def record_activity(run, event_type)
      return unless run.board_task_id.present?

      board = run.board_task.board
      BoardActivity.create!(
        board: board, board_task: run.board_task, event_type: event_type,
        actor: run.user, actor_type: :system,
        metadata: { workflow_name: run.workflow.name, workflow_run_id: run.id }
      )
      board.touch
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Failed to record activity for run ##{run.id}: #{e.message}")
    end
  end
end
