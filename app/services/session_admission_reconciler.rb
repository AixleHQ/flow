# frozen_string_literal: true

class SessionAdmissionReconciler
  def self.run(limit: 100)
    # Durable run stop markers repair a crash during cancellation fan-out.
    WorkflowRun.where.not(stop_requested_at: nil).where(state: %w[running paused cancelled])
      .joins(:step_runs).where(step_runs: { state: %w[pending running waiting_input] }).distinct.limit(limit).each do |run|
      WorkflowService.repair_cancellation(run)
    end
    SessionLaunchRelay.drain(limit: limit)
    # Admissions with an unresolved operation used to be skipped entirely, which
    # is how a wedged one stayed invisible for hours: nothing looked at it, and
    # its workload kept running. They are examined like any other now — the
    # operation still holds the reservation, but the runtime gets cleaned up and
    # the operation gets an honest label.
    SessionAdmission.occupied.where(launch_state: %w[acknowledged claimed]).order(:updated_at).limit(limit).each do |admission|
      next unless TemporalService.enabled?
      admission.touch
      next if execution_open?(admission.terminal_session.workflow_id)

      strand_in_flight_operations(admission)
      Activities::Container::AdmittedPhaseActivity.new.run(Hashie::Mash.new(
        phase: "cleanup", admission_id: admission.id, error: admission.terminal_session.finished? ? nil : "Container workflow ended"
      ))
    rescue StandardError => e
      admission.update!(last_error: "Reconciliation: #{e.class}: #{e.message}")
    end
    report(snapshot)
  end

  # Whether Temporal still has a running execution behind this reservation.
  #
  # Unlike workflow_open?, transport errors propagate: unknown is never closed,
  # because cleaning up behind a workflow that is merely unreachable would race
  # its own cleanup. NOT_FOUND is the one negative answer that is not a
  # transport failure — the server looked and has no such execution, whether
  # because the launch never reached Temporal or because retention expired.
  # Nothing can ever report a result for an execution that does not exist, so
  # treating it as "unknown" pinned the slot forever: the reservation recorded
  # the same error every minute and never reached cleanup.
  def self.execution_open?(workflow_id)
    description = TemporalService.client.workflow_handle(workflow_id).describe
    description.status == Temporalio::Client::WorkflowExecutionStatus::RUNNING
  rescue Temporalio::Error::RPCError => e
    raise unless e.code == Temporalio::Error::RPCError::Code::NOT_FOUND

    Rails.logger.warn("[SessionAdmission] Temporal has no execution #{workflow_id}; reconciling as closed")
    false
  end

  # An in-flight operation means "a create is running right now", which is true
  # only while something is running it. Once the workflow is closed, no activity
  # can ever report that result, so the honest label is `uncertain` — and that is
  # the number an operator is alerted on. Left as in_flight it reads as ordinary
  # provisioning load and a pinned slot stays silent.
  def self.strand_in_flight_operations(admission)
    stranded = admission.session_runtime_operations.where(state: "in_flight")
    return if stranded.empty?

    stranded.update_all(state: "uncertain", error: "Container workflow closed before this operation reported", updated_at: Time.current)
    Rails.logger.warn("[SessionAdmission] admission #{admission.id}: #{stranded.size} operation(s) stranded by a closed workflow")
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
  # fault.
  #
  # `pinned_reservations` is the one to alert on, and it is narrower than
  # `uncertain_operations`: only an unresolved create or start can still put a
  # workload on the cluster, so only those hold a slot
  # (SessionRuntimeOperation::MATERIALIZING_PHASES). An unaccountable `exec` is
  # still worth seeing — it means a session died mid-launch — but it costs no
  # capacity, and counting it as pinned sent operators after slots that were
  # never taken.
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
      pinned_reservations: SessionRuntimeOperation.pinning.count,
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
