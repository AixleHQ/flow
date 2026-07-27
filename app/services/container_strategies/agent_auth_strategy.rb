# frozen_string_literal: true

module ContainerStrategies
  # AgentAuthStrategy
  # Strategy for agent authentication containers.
  #
  # Auth-specific:
  #   - before_cleanup: extracts auth files, saves AgentCredential
  #   - phase_config: exec awaits container_finished signal
  #
  class AgentAuthStrategy < AgentBaseStrategy
    def phase_config(phase)
      case phase
      when :pull_image  then { timeout: 600 }
      when :exec        then { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
      when :cleanup     then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
      else                   { timeout: 300 }
      end
    end

    # == before_exec(container_id:, **) → {} ==
    # Seed the files the CLI needs before it launches, for this auth kind. Default
    # ("agent") is the adapter's fresh-login setup files; other kinds (e.g. Claude's
    # "design") return the user's existing credential so the CLI starts logged in.
    # Everything kind-specific lives in the adapter — this strategy stays generic.

    def before_exec(container_id:, **)
      container = resolve_container(container_id)

      # uid/gid must be the agent user, not root. A root-owned file under the agent's
      # HOME is readable but not writable, which breaks any login flow that needs to
      # create sibling state next to its config (e.g. `aws sso login` writing
      # ~/.aws/sso/cache/ next to a seeded ~/.aws/config).
      uid = adapter.container_uid

      adapter.auth_setup_files_for(auth_kind, current_credential_config).each do |path, content|
        wrote = runtime.write_file(container, path, content, uid: uid, gid: uid)
        if wrote == false
          Rails.logger.error("[AgentAuth] FAILED to write auth setup file: #{path}")
        else
          Rails.logger.info("[AgentAuth] Wrote auth setup file: #{path}")
        end
      end

      {}
    end

    # == exec ==
    # When the adapter provides launch commands for this kind, the entrypoint started
    # `bash` (see #ttyd_command) and we launch the CLI here — AFTER before_exec seeded
    # the credentials — then drive any follow-up commands (e.g. a slash command).

    def exec(container_id:, **)
      result = super

      commands = adapter.auth_launch_commands_for(auth_kind)
      send_tmux_sequence(resolve_container(container_id), commands) if commands.any?

      result
    end

    # == before_cleanup(container_id:, session_id:, **) → { auth_completed:, credential_id: } ==
    # Persists a credential ONLY when auth actually completed (a real token is
    # present). Cleanup runs unconditionally (always: true), and the agent's
    # config file may exist without a token — so gating on completion is what
    # prevents an empty/garbage credential from being created on a failed/aborted login.

    def before_cleanup(container_id: nil, session_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = session_id ? TerminalSession.find(session_id) : nil
      agent_service = AgentCredentialsService.for(input[:agent_type])

      auth_files = extract_auth_files(container, agent_service)
      completed = auth_files.any? { |_p, content| content.present? && agent_service.adapter.auth_complete_for?(auth_kind, content) }
      result = { auth_completed: completed }

      if completed && session.present?
        credential = save_credentials(session, auth_files, agent_service)
        if credential
          result[:credential_id] = credential.id
          Rails.logger.info("[AgentAuth] Credential saved: #{credential.id}")
        end
      else
        Rails.logger.info("[AgentAuth] before_cleanup: auth not complete (#{auth_files.size} files) — no credential saved")
      end

      result
    end

    # Override the watched keys per auth kind (the adapter decides; default is the
    # standard login keys).
    def build_env_vars
      vars = super
      upsert_env_var(vars, "AUTH_REQUIRED_KEYS", adapter.auth_required_keys_for(auth_kind).join(","))
      vars
    end

    protected

    def session_type = "auth_setup"

    def ttyd_command
      # If the adapter drives its own launch (kinds that seed creds first, then send
      # commands post-seed), start `bash`; otherwise the entrypoint launches the agent's
      # login command at container start (a fresh login).
      adapter.auth_launch_commands_for(auth_kind).any? ? "bash" : AUTH_COMMANDS.fetch(input[:agent_type])
    end

    private

    # Opaque auth kind carried on the session ("agent" = normal login). The adapter
    # interprets it; this strategy never branches on specific values.
    def auth_kind
      current_terminal_session&.metadata&.dig("auth_kind").presence || "agent"
    end

    def adapter
      @adapter ||= AgentCredentialsService.for(input[:agent_type]).adapter
    end

    # The user's currently-stored credential config for this agent (nil if none) —
    # passed to the adapter so a kind that layers on an existing login can seed it.
    def current_credential_config
      AgentCredential.find_by(user_id: input[:user_id], agent_type: input[:agent_type])&.config_data
    end

    def save_credentials(session, auth_files, agent_service)
      adapter = agent_service.adapter
      captured = build_credentials_from_files(auth_files, adapter)
      return nil if captured.blank?

      # Reconcile the scrape against what's already stored for this kind. Default is a
      # full replace; a layering kind (e.g. design) only adds its own block so it never
      # re-captures the base it seeded into the container.
      current = AgentCredential.find_by(user_id: session.user_id, agent_type: input[:agent_type])&.config_data
      config_data = adapter.reconcile_captured_credentials(auth_kind, current, captured)
      return nil if config_data.blank?

      AgentCredential.from_artifacts(session.user_id, SessionCompany.company_id_for(session), input[:agent_type], config_data)
    end
  end
end
