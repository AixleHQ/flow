# frozen_string_literal: true

class SessionLaunchRelay
  # How long a claim is somebody's to finish. Claiming commits before the
  # preflight and the Temporal start, so for this long an admission can be
  # `claimed` with no execution behind it yet and still be perfectly healthy —
  # a dispatcher is simply mid-launch. Anything reading launch state has to
  # honour the lease (SessionAdmissionReconciler does), or it reaps live
  # launches; anything past it is fair to take over, because the process that
  # held it is gone.
  CLAIM_LEASE = 2.minutes

  def self.drain(limit: 100)
    SessionAdmissionService.drain!(limit: limit)
    SessionAdmission.occupied.where(launch_state: %w[pending claimed], stop_requested_at: nil)
      .where("claimed_at IS NULL OR claimed_at <= ?", CLAIM_LEASE.ago).order(:id).limit(limit).each do |admission|
      dispatch(admission)
    end
  end

  def self.dispatch(admission)
    claim = SecureRandom.uuid
    session = nil
    start_attempted = false
    SessionAdmissionService.transaction do
      admission.reload.lock!
      return if admission.released_at || admission.stop_requested_at
      return if admission.launch_state == "acknowledged"
      return if admission.claimed_at && admission.claimed_at > CLAIM_LEASE.ago
      session = admission.terminal_session
      SessionAdmissionService.ensure_run_active!(session)
      admission.update!(launch_state: "claimed", claimed_at: Time.current, claim_token: claim)
    end

    SessionService.revalidate_admission!(session, refresh_tokens: true)
    start_attempted = true
    result = TemporalService.start_workflow(
      TemporalWorkflowRegistry.container_workflow_v2,
      { session_id: session.id, admission_id: admission.id, permit_token: admission.permit_token, manifest: session.strategy.build_manifest },
      id: session.workflow_id, execution_timeout: TerminalSession::WORKFLOW_TIMEOUT, reject_duplicate: true
    )
    raise result[:error].to_s unless result[:ok]

    SessionAdmissionService.transaction do
      admission.reload.lock!
      next if admission.released_at || admission.claim_token != claim
      admission.update!(launch_state: "acknowledged")
      session.update!(temporal_workflow_id: session.workflow_id, temporal_run_id: result[:run_id])
    end
  rescue SessionAdmissionService::Stopped, Oauth::PreflightError, CloudAuth::PreflightError,
         AgentCredential::PreflightError, SessionService::UnsafeMcpUrlError => e
    admission.update!(last_error: e.message)
    if session && !start_attempted
      SessionAdmissionService.transaction do
        admission.reload.lock!
        if admission.claim_token == claim
          admission.update!(launch_state: "pending", claimed_at: nil)
          SessionAdmissionService.cancel!(session)
          # The refusal has to reach the session too. Only the admission carried
          # it, and nothing on the board reads that — a step refused at the gate
          # showed up as a bare "cancelled" with an empty error, so the run's
          # owner had no way to learn that a connection needed reconnecting.
          session.reload.update!(
            error_message: TerminalSession.preferred_error_message(session.error_message, e.message)
          )
        end
      end
    end
  rescue StandardError => e
    admission.update!(last_error: "#{e.class}: #{e.message}")
    Rails.logger.warn("[SessionLaunchRelay] Admission #{admission.id}: #{e.message}")
  end
end
