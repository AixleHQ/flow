# frozen_string_literal: true

class SessionLaunchRelay
  def self.drain(limit: 100)
    SessionAdmissionService.drain!(limit: limit)
    SessionAdmission.occupied.where(launch_state: %w[pending claimed], stop_requested_at: nil)
      .where("claimed_at IS NULL OR claimed_at <= ?", 2.minutes.ago).order(:id).limit(limit).each do |admission|
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
      return if admission.claimed_at && admission.claimed_at > 2.minutes.ago
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
        end
      end
    end
  rescue StandardError => e
    admission.update!(last_error: "#{e.class}: #{e.message}")
    Rails.logger.warn("[SessionLaunchRelay] Admission #{admission.id}: #{e.message}")
  end
end
