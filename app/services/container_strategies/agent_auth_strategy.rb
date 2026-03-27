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
        runtime.copy_to(container, path, content)
        Rails.logger.info("[AgentAuth] Wrote auth setup file: #{path}")
      end

      {}
    end

    # == before_cleanup(container_id:, session_id:, **) → { auth_files:, credential_id: } ==

    def before_cleanup(container_id: nil, session_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = session_id ? TerminalSession.find(session_id) : nil
      agent_service = AgentCredentialsService.for(input[:agent_type])

      auth_files = extract_auth_files(container, agent_service)
      result = { auth_files: auth_files, auth_completed: auth_files.any? }

      if auth_files.any? && session.present?
        credential = save_credentials(session, auth_files)
        result[:credential_id] = credential.id
        Rails.logger.info("[AgentAuth] Credential saved: #{credential.id}")
      end

      Rails.logger.info("[AgentAuth] before_cleanup: #{auth_files.size} files")
      result
    end

    protected

    def session_type = "auth_setup"

    def ttyd_command
      AUTH_COMMANDS.fetch(input[:agent_type])
    end

    private

    def extract_auth_files(container, agent_service)
      auth_files = {}

      paths = if agent_service.adapter.respond_to?(:auth_file_paths)
                agent_service.adapter.auth_file_paths
      else
                [ agent_service.config_path ]
      end

      paths.each do |path|
        content = read_file_from_container(container, path)
        auth_files[path] = content if content.present?
      rescue StandardError => e
        Rails.logger.warn("[AgentAuth] Failed to extract #{path}: #{e.message}")
      end

      auth_files
    end

    def save_credentials(session, auth_files)
      adapter = AgentCredentialsService.for(input[:agent_type]).adapter
      container = resolve_container(auth_files.values.first ? nil : nil) rescue nil

      config_data = {}
      auth_files.each do |path, content|
        basename = File.basename(path)

        # Encrypted credential files (e.g. Gemini API key) — try to decrypt
        if basename == "gemini-credentials.json" && adapter.respond_to?(:decrypt_credentials_file)
          hostname = extract_container_hostname
          api_key = adapter.decrypt_credentials_file(content, hostname)
          config_data["api_key"] = api_key if api_key
          next
        end

        parsed = JSON.parse(content)
        if basename == "settings.json"
          # Skip settings — not needed in stored credentials
        else
          config_data.merge!(parsed)
        end
      rescue JSON::ParserError
        config_data["_raw_#{basename}"] = content
      rescue StandardError => e
        Rails.logger.warn("[AgentAuth] Failed to process #{path}: #{e.message}")
      end

      AgentCredential.from_artifacts(session.user_id, input[:agent_type], config_data)
    end

    def extract_container_hostname
      session = TerminalSession.find(input[:session_id])
      container = resolve_container(session.container_id)
      result = runtime.exec(container, [ "hostname" ])
      result[0].join.strip
    rescue StandardError
      ""
    end
  end
end
