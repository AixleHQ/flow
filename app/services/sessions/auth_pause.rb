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
  class AuthPause
    # The heal counters outlive a pause: a grant that keeps getting refused must not be
    # retried for every episode it causes.
    PAUSE_KEYS = %w[auth_paused_at auth_pause_reason].freeze

    # The banner has to be the last thing the agent did, a minute ago at least.
    QUIET_BEFORE_PAUSE = 1.minute
    # Read from the end of the pane: Claude Code draws its prompt box and status line below
    # the banner, a few lines each.
    TAIL_LINES = 40

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

    # One look at a live session's pane (ScanQuotaErrorsActivity, once a minute).
    # @return [Symbol, nil] :paused, :resumed, :failed, or nil when the pane shows no refused login
    def observe(pane)
      return nil if pane.blank? # the pane could not be read: nothing to decide on
      return continue(pane) if self.class.paused?(session)

      banner = banner_in(pane)
      return nil if banner.nil? || !quiet?

      pause!(banner)
      heal!
      self.class.paused?(session.reload) ? :paused : :resumed
    end

    # The session's container holds a working login again. Types the prompt that sends the
    # agent back to its task.
    # @return [Boolean] whether the session was paused and has been resumed
    def resume!
      return false unless self.class.paused?(session)
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

    private

    attr_reader :session

    # Only what the pane says can end a pause. Its log's mtime cannot: opening the session's
    # terminal in a browser redraws the CLI and moves it.
    def continue(pane)
      return unpause_quietly if banner_in(pane).nil?
      return expire! if paused_at < self.class.limit.ago

      heal! if heal_due?
      self.class.paused?(session.reload) ? :paused : :resumed
    end

    def banner_in(pane)
      pattern = adapter.auth_banner_pattern
      return nil if pattern.nil?

      lines = pane.to_s.dup.force_encoding(Encoding::UTF_8).scrub.lines.map(&:rstrip).reject(&:empty?).last(TAIL_LINES)
      banner_at = lines.rindex { |line| line.match?(pattern) }
      return nil if banner_at.nil?

      marker = adapter.auth_resume_prompt[0, 30]
      nudged_at = lines.rindex { |line| line.include?(marker) }
      return nil if nudged_at && nudged_at > banner_at

      lines[banner_at].strip.truncate(500)
    end

    # False when the container cannot say: an unknown pane is not a quiet one.
    def quiet?
      last_output_at.present? && last_output_at < QUIET_BEFORE_PAUSE.ago
    end

    def last_output_at
      return @last_output_at if defined?(@last_output_at)

      tail = Sessions::LiveLogReader.new(session, runtime: container_runtime).tail(lines: 1)
      @last_output_at = tail.status == :ok ? tail.last_output_at : nil
    end

    def pause!(banner)
      session.merge_jsonb!(:metadata, "auth_paused_at" => Time.current.iso8601, "auth_pause_reason" => banner)
      run = session.step_run&.workflow_run
      run.pause! if run&.may_pause?
      log(:info, "paused: #{banner}")
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
      Agents::CredentialDelivery.new(runtime: container_runtime).deliver(credential, sessions: holders)
    end

    def heal_due?
      return false if heal_attempts >= MAX_HEAL_ATTEMPTS

      attempted = Time.zone.parse(session.metadata["auth_heal_attempted_at"].to_s)
      attempted.nil? || attempted < HEAL_INTERVAL.ago
    end

    def heal_attempts
      session.metadata["auth_heal_attempts"].to_i
    end

    def fresh_grant?(credential)
      granted = Time.zone.parse(credential.metadata&.dig("refresh_token_granted_at").to_s)
      granted.present? && granted > FRESH_GRANT.ago
    end

    def expire!
      reason = session.metadata["auth_pause_reason"].presence || "login expired"
      SessionService.fail_session(
        session: session,
        error_message: "Session terminated: agent authentication failed — #{reason}. " \
                       "Nobody signed in again within #{self.class.limit.inspect}."
      )
      log(:info, "nobody signed in again; failed")
      :failed
    end

    # The banner left the pane's tail: someone signed in from the session's own terminal, or
    # the agent went on by itself.
    def unpause_quietly
      unpause!
      log(:info, "is working again")
      :resumed
    end

    def unpause!
      session.remove_jsonb_keys!(:metadata, *PAUSE_KEYS)
      run = session.step_run&.workflow_run
      return unless run&.paused?
      return if run.step_runs.joins(:terminal_session).merge(TerminalSession.active.auth_paused).exists?

      run.resume!
    end

    def nudge
      return false if session.container_id.blank?

      container = container_runtime.resolve_container(session.container_id)
      typed = container_runtime.exec(container, [ "tmux", "send-keys", "-t", "agent", "-l", adapter.auth_resume_prompt ])
      return false unless Array(typed)[2].to_i.zero?

      Array(container_runtime.exec(container, [ "tmux", "send-keys", "-t", "agent", "Enter" ]))[2].to_i.zero?
    rescue StandardError => e
      log(:warn, "could not type the resume prompt: #{e.class}: #{e.message}")
      false
    end

    def paused_at
      Time.zone.parse(session.metadata["auth_paused_at"].to_s) || Time.current
    end

    def session_credential
      SessionCompany.agent_credentials_for(session).find_by(agent_type: session.agent_type)
    end

    def adapter
      @adapter ||= AgentCredentialsService.for(session.agent_type).adapter
    end

    def container_runtime
      @runtime ||= ContainerRuntime.build
    end

    def log(level, message)
      Rails.logger.public_send(level, "[AuthPause] session=#{session.id} #{message}")
      nil
    end
  end
end
