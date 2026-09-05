# frozen_string_literal: true

class SessionAdmissionReconciler
  def self.run(limit: 100)
    # Durable run stop markers repair a crash during cancellation fan-out.
    WorkflowRun.where.not(stop_requested_at: nil).where(state: %w[running paused cancelled])
      .joins(:step_runs).where(step_runs: { state: %w[pending running waiting_input] }).distinct.limit(limit).each do |run|
      WorkflowService.send(:cancel_active_step_runs, run)
    end
    SessionLaunchRelay.drain(limit: limit)
    unresolved = SessionRuntimeOperation.where(state: %w[in_flight uncertain]).select(:session_admission_id)
    SessionAdmission.occupied.where(launch_state: %w[acknowledged claimed]).where.not(id: unresolved).order(:updated_at).limit(limit).each do |admission|
      next unless TemporalService.enabled?
      admission.touch
      # Unlike workflow_open?, transport errors propagate: unknown is never closed.
      description = TemporalService.client.workflow_handle(admission.terminal_session.workflow_id).describe
      next if description.status == Temporalio::Client::WorkflowExecutionStatus::RUNNING
      Activities::Container::AdmittedPhaseActivity.new.run(Hashie::Mash.new(
        phase: "cleanup", admission_id: admission.id, error: admission.terminal_session.finished? ? nil : "Container workflow ended"
      ))
    rescue StandardError => e
      admission.update!(last_error: "Reconciliation: #{e.class}: #{e.message}")
    end
  end
end
