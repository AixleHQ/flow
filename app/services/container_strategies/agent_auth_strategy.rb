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
    # Write agent-specific config files needed before auth starts
    # (e.g. Codex config.toml with cli_auth_credentials_store = "file")

    def before_exec(container_id:, **)
      container = resolve_container(container_id)
      adapter = AgentCredentialsService.for(input[:agent_type]).adapter

      adapter.auth_setup_files.each do |path, content|
        runtime.write_file(container, path, content)
        Rails.logger.info("[AgentAuth] Wrote auth setup file: #{path}")
      end

      {}
    end

    # == before_cleanup(container_id:, session_id:, **) → { auth_completed:, credential_id: } ==
    # Persists a credential ONLY when auth actually completed (a real token is
    # present). Cleanup runs unconditionally (always: true), and the agent's
    # config file may exist without a token — so gating on auth_complete? is what
    # prevents an empty/garbage credential from being created on a failed/aborted login.

    def before_cleanup(container_id: nil, session_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = session_id ? TerminalSession.find(session_id) : nil
      agent_service = AgentCredentialsService.for(input[:agent_type])

      auth_files = extract_auth_files(container, agent_service)
      completed = auth_files_complete?(auth_files, agent_service)
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

    protected

    def session_type = "auth_setup"

    def ttyd_command
      AUTH_COMMANDS.fetch(input[:agent_type])
    end

    private

    def save_credentials(session, auth_files, agent_service)
      config_data = build_credentials_from_files(auth_files, agent_service.adapter)
      return nil if config_data.blank?

      AgentCredential.from_artifacts(session.user_id, input[:agent_type], config_data)
    end
  end
end
