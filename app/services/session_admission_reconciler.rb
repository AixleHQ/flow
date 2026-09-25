# frozen_string_literal: true

class SessionAdmissionReconciler
  # A stop whose cancel never reached Temporal left the workflow — and its
  # reservation — running until the day-long execution timeout. Past this, the
  # cancel is sent again on every pass until the execution closes.
  CANCEL_RETRY_AFTER = 2.minutes

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
    #
    # A claim within its lease is excluded, and that exclusion is the whole
    # point of the lease. `claimed` commits before the preflight and the
    # Temporal start, so a launch that is going perfectly spends seconds as
    # `claimed` with nothing in Temporal to describe — and this pass, which
    # reads "no execution" as "closed", reaped it. In production that ended 69
    # sessions between 2026-09-05 and 2026-09-18: killed within a second or two
    # of being claimed, `started_at` never set, no runtime operation ever
    # created, and the owner told "Container workflow ended" about a container
    # that was never built. Past the lease the dispatcher that held it is gone,
    # the relay above has already had its turn to take the claim over, and
    # whatever is left really is abandoned.
    SessionAdmission.occupied.where(launch_state: %w[acknowledged claimed])
      .where("launch_state <> 'claimed' OR claimed_at IS NULL OR claimed_at <= ?", SessionLaunchRelay::CLAIM_LEASE.ago)
      .order(:updated_at).limit(limit).each do |admission|
      next unless TemporalService.enabled?
      admission.touch
      next resend_cancel(admission) if execution_open?(admission.terminal_session.workflow_id)

      strand_in_flight_operations(admission)
      Activities::Container::AdmittedPhaseActivity.new.run(TemporalInput.wrap(
        phase: "cleanup", admission_id: admission.id, error: cleanup_error(admission)
      ))
    rescue StandardError => e
      admission.update!(last_error: "Reconciliation: #{e.class}: #{e.message}")
    end
    report(snapshot)
  end

  # What actually happened, in terms of the thing the owner was promised.
  #
  # Both halves of this used to be told "Container workflow ended", and the half
  # it was wrong about is the half people came asking about. A launch abandoned
  # before it reached the container has no container to have ended: no log, no
  # `started_at`, no runtime operation, nothing to open. The sentence sent every
  # one of those investigations hunting a crash that had not happened. A session
  # that really did get a container keeps the original wording, because for it
  # the sentence was true.
  def self.cleanup_error(admission)
    session = admission.terminal_session
    return nil if session.finished?
    return "Container workflow ended" if session.started_at || admission.runtime_id.present?

    TerminalSession::LAUNCH_ABANDONED_ERROR
  end

  def self.resend_cancel(admission)
    return if admission.stop_requested_at.nil? || admission.stop_requested_at > CANCEL_RETRY_AFTER.ago

    result = TemporalService.cancel_workflow(admission.terminal_session.workflow_id)
    return if result[:ok]

    admission.update!(last_error: "Cancel not delivered: #{result[:error]}")
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
                              .where(terminal_sessions: { state: TerminalSession::TERMINAL_STATES })
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
      # Of those, the ones whose absence is already being timed. A pin that is
      # counted here is on its way out; one that is not is either waiting for
      # this pass to prove absence or waiting for a human, and only the second
      # is worth waking anybody for.
      pinned_confirming: SessionRuntimeOperation.pinning.where.not(absent_since: nil).count,
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
