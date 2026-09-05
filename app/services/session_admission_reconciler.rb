# frozen_string_literal: true

class SessionAdmissionReconciler
  def self.run(limit: 100)
    # Durable run stop markers repair a crash during cancellation fan-out.
    WorkflowRun.where.not(stop_requested_at: nil).where(state: %w[running paused cancelled])
      .joins(:step_runs).where(step_runs: { state: %w[pending running waiting_input] }).distinct.limit(limit).each do |run|
      WorkflowService.repair_cancellation(run)
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
    report(snapshot)
  end

  # The numbers that distinguish "the queue is working" from "the queue is
  # wedged": how long the head has been waiting, how much capacity is pinned by
  # an unprovable runtime operation, how long confirmed cleanup is lagging, and
  # whether anyone is blocked at all. Emitted once per pass as one structured
  # line, which is what the cluster's log pipeline can alert on without the app
  # taking on a metrics backend.
  #
  # in_flight and uncertain are counted apart on purpose. An in-flight operation
  # is a create that is simply still running — every provisioning session has
  # one, so folding it into the alerting number makes normal load look like a
  # fault. Only `uncertain` means capacity is pinned until an operator resolves
  # it.
  def self.snapshot
    now = Time.current
    queued = SessionAdmission.unreleased.where(admitted_at: nil, stop_requested_at: nil)
    lagging = SessionAdmission.occupied.joins(:terminal_session)
                              .where(terminal_sessions: { state: %w[finished failed cancelled] })
    policy = SessionAdmissionPolicy.current

    {
      enabled: policy.enabled?,
      paused: policy.paused?,
      queued: queued.count,
      occupied: SessionAdmission.occupied.count,
      pools_with_queue: SessionAdmissionPool.where(id: queued.select(:session_admission_pool_id)).count,
      oldest_queue_wait_seconds: age(queued.minimum(:created_at), now),
      operations_in_flight: SessionRuntimeOperation.where(state: "in_flight").count,
      uncertain_operations: SessionRuntimeOperation.where(state: "uncertain").count,
      cleanup_lag_seconds: age(lagging.minimum(:updated_at), now)
    }
  end

  def self.age(timestamp, now) = timestamp ? (now - timestamp).to_i : 0

  def self.report(stats)
    Rails.logger.info("[SessionAdmission] queue health #{stats.to_json}")
    stats
  end
  private_class_method :report
end
