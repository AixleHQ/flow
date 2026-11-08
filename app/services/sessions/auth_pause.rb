# frozen_string_literal: true

module Sessions
  # Holds a workflow step whose agent lost its login instead of letting it die.
  #
  # Claude Code does not exit when its login is refused: it prints a banner and waits at its
  # prompt, with the conversation and the workspace intact. That wait used to end 30 minutes
  # later in the no-output watchdog, which failed the step, failed the run, cancelled the
  # sibling steps and deleted the container holding the work.
  #
  # A paused session is exempt from that watchdog. The credential is renewed when the
  # platform can do it itself — the common case, because the grant usually died of another
  # container spending the shared refresh token first — and Agents::CredentialDelivery hands
  # the result to every holder, typing #resume!'s prompt into each paused one. A login nobody
  # can renew waits for its owner to sign in again, which is delivered the same way, until
  # the pause limit fails the session as before.
  #
  # This class holds the actions: pausing, healing, expiring and resuming. Deciding from
  # a workflow step's pane when to take them is Sessions::Checks::AuthPause's, on the
  # snapshot Sessions::Monitor reads once a minute; a refused login written back by the CLI
  # reaches #login_refused! without any pane read.
  class AuthPause
    # The heal counters outlive a pause: a grant that keeps getting refused must not be
    # retried for every episode it causes.
    PAUSE_KEYS = %w[auth_paused_at auth_pause_reason].freeze

    # Each attempt is a refresh against the vendor; repeating one sooner only repeats its answer.
    HEAL_INTERVAL = 5.minutes
    MAX_HEAL_ATTEMPTS = 3
    # A refresh token granted this recently is newer than the one the agent was refused:
    # handing it over is the whole repair, with no refresh spent on it.
    FRESH_GRANT = 10.minutes
    FORCE_REFRESH_MARGIN_MS = 100.years.in_milliseconds

    def self.paused?(session)
      session.metadata&.dig("auth_paused_at").present?
    end

    def self.limit
      Settings.agents.auth_pause_limit_minutes.to_i.minutes
    end

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    # The CLI in this session's container was refused its refresh and blanked its own
    # credentials (AgentCredentialSyncController: the write-back of that blank block). Read
    # off the write-back rather than the pane, so it reaches interactive sessions too without
    # an exec into every one of them every minute.
    def login_refused!
      return if self.class.paused?(session)
      return unless pause!("The #{adapter_label} login was refused in this session")

      credential = session_credential
      return unless credential&.active?

      # The stored grant still works (another holder renewed it, or only this copy was bad):
      # hand it over. A dead one waits for its owner to sign in again.
      TemporalService.start_workflow(
        TemporalWorkflowRegistry.workflows["agent_credential_fan_out_workflow"],
        { credential_id: credential.id, origin_session_id: nil },
        id: "agent-credential-fan-out-#{credential.id}-#{SecureRandom.hex(6)}"
      )
    end

    # The session's container holds a working login again. A workflow step is sent back to
    # its task with a typed prompt. An interactive session is not typed into, because a person
    # may be typing there; its page says the login was renewed instead.
    # @return [Boolean] whether the session was paused and has been resumed
    def resume!
      return false unless self.class.paused?(session)

      if interactive_session?
        unpause!(renewed: true)
        log(:info, "login renewed")
        return true
      end
      return false unless nudge

      unpause!
      log(:info, "resumed")
      true
    rescue StandardError => e
      # Called from a delivery loop: one holder that cannot be resumed must not cost the
      # others their token. The next scan resumes it or lets it go.
      log(:warn, "could not resume: #{e.class}: #{e.message}")
      false
    end

    # Records the pause, then pauses the workflow run. A compare-and-set under the session's
    # row lock: a session that is already paused, or for which `still` (when given) no longer
    # holds, is left as it is.
    # @return [Boolean] whether the session was paused
    def pause!(banner, &still)
      paused = session.with_lock do
        next false if self.class.paused?(session) || (still && !still.call(session))

        session.update_jsonb_keys!(:metadata, set: { "auth_paused_at" => Time.current.iso8601,
                                                     "auth_pause_reason" => banner },
                                              remove: %w[auth_renewed_at])
        true
      end
      return false unless paused

      announce
      run = session.step_run&.workflow_run
      run.pause! if run&.may_pause?
      log(:info, "paused: #{banner}")
      true
    end

    # Renews the login if the platform can, then hands whatever is stored to every holder,
    # here in the worker. Delivery is what resumes this session, so it runs even when no
    # refresh was needed.
    def heal!
      credential = session_credential
      return unless credential&.active?

      session.merge_jsonb!(:metadata, "auth_heal_attempts" => heal_attempts + 1,
                                      "auth_heal_attempted_at" => Time.current.iso8601)
      unless fresh_grant?(credential)
        result = AgentCredential.delivering_inline do
          credential.renew!(source: :auth_pause, margin_ms: FORCE_REFRESH_MARGIN_MS, blocks: adapter.base_refresh_blocks)
        end
        credential.await_refresh if result[:status] == :busy
        return log(:warn, "could not renew credential #{credential.id}: #{result[:detail]}") if result[:status] == :error
      end

      holders = credential.reload.live_holder_sessions.where.not(container_id: [ nil, "" ]).to_a
      # Not this session's runtime: each holder is written through its own
      # (ContainerRuntime.for_session), a runner's or the hosted one.
      Agents::CredentialDelivery.new.deliver(credential, sessions: holders)
    end

    def heal_due?
      return false if heal_attempts >= MAX_HEAL_ATTEMPTS

      attempted = Time.zone.parse(session.metadata["auth_heal_attempted_at"].to_s)
      attempted.nil? || attempted < HEAL_INTERVAL.ago
    end

    # Nobody signed in again within the pause limit.
    def expired?
      paused_at < self.class.limit.ago
    end

    # Fails the session after the pause limit: a compare-and-set
    # (SessionService.fail_session_if), so a session that was unpaused, or started
    # finishing, since it was read is left as it is.
    # @return [Boolean] whether the session was failed
    def expire!(&still)
      reason = session.metadata["auth_pause_reason"].presence || "login expired"
      failed = SessionService.fail_session_if(
        session: session, expected_state: session.state,
        error_message: "Session terminated: agent authentication failed — #{reason}. " \
                       "Nobody signed in again within #{self.class.limit.inspect}."
      ) { |locked| self.class.paused?(locked) && (still.nil? || still.call(locked)) }
      log(:info, failed ? "nobody signed in again; failed" : "no longer paused; not failed")
      failed
    end

    # The banner left the pane's tail: someone signed in from the session's own terminal, or
    # the agent went on by itself.
    # @return [Boolean] whether the session was unpaused
    def unpause_quietly(&still)
      return false unless unpause!(&still)

      log(:info, "is working again")
      true
    end

    private

    attr_reader :session

    def heal_attempts
      session.metadata["auth_heal_attempts"].to_i
    end

    def fresh_grant?(credential)
      granted = Time.zone.parse(credential.metadata&.dig("refresh_token_granted_at").to_s)
      granted.present? && granted > FRESH_GRANT.ago
    end

    # Under the session's row lock, as #pause!: a session another path unpaused meanwhile
    # (a delivery's #resume!, a pass's #unpause_quietly) is not unpaused twice.
    def unpause!(renewed: false, &still)
      unpaused = session.with_lock do
        next false unless self.class.paused?(session) && (still.nil? || still.call(session))

        session.update_jsonb_keys!(:metadata, set: renewed ? { "auth_renewed_at" => Time.current.iso8601 } : {},
                                              remove: PAUSE_KEYS)
        true
      end
      return false unless unpaused

      announce
      run = session.step_run&.workflow_run
      return true unless run&.paused?
      return true if run.step_runs.joins(:terminal_session).merge(TerminalSession.active.auth_paused).exists?

      run.resume!
      true
    end

    def nudge
      PaneInput.type(session, adapter.auth_resume_prompt, runtime: container_runtime)
    end

    def paused_at
      Time.zone.parse(session.metadata["auth_paused_at"].to_s) || Time.current
    end

    def interactive_session?
      session.session_type != "workflow_step"
    end

    # The jsonb writes skip callbacks, so the session's page would not hear about them.
    def announce
      session.touch
    end

    def adapter_label
      session.agent_type.to_s.titleize
    end

    def session_credential
      SessionCompany.agent_credentials_for(session).find_by(agent_type: session.agent_type)
    end

    def adapter
      @adapter ||= AgentCredentialsService.for(session.agent_type).adapter
    end

    def container_runtime
      @runtime ||= ContainerRuntime.for_session(session)
    end

    def log(level, message)
      Rails.logger.public_send(level, "[AuthPause] session=#{session.id} #{message}")
      nil
    end
  end
end
