# frozen_string_literal: true

module ContainerStrategies
  # AgentSessionStrategy
  # Strategy for starting agent session containers with pre-loaded credentials
  #
  # Inherits from AgentAuthStrategy and adds:
  #   - MCP configuration for tool access
  #   - Credential loading in before_exec
  #   - Session artifact collection
  #
  # Input:
  #   - user_id: User ID
  #   - agent_type: claude_code | cursor_cli | codex | gemini_cli
  #   - session_id: TerminalSession ID
  #   - route_token: Random token for URL routing
  #   - credential: AgentCredential instance (optional)
  #
  # @example
  #   strategy = AgentSessionStrategy.new(
  #     user_id: 1,
  #     agent_type: "claude_code",
  #     session_id: 123,
  #     route_token: "abc123",
  #     credential: agent_credential
  #   )
  #   result = ContainerService.execute(strategy: strategy, input: strategy.input)
  #
  class AgentSessionStrategy < AgentAuthStrategy
    # == Template Methods ==

    def build_env_vars
      base_vars = super

      # Change SESSION_TYPE
      base_vars.map! { |v| v.sub("SESSION_TYPE=auth_setup", "SESSION_TYPE=agent_session") }

      # Change TTYD_CMD to session command (base command with flag, no prompt value)
      base_vars.map! { |v| v.sub(/^TTYD_CMD=.*$/, "TTYD_CMD=#{ttyd_command}") }

      session = TerminalSession.find(input[:session_id])

      # Pass prompt as separate env var for non-interactive sessions.
      # Entrypoint writes it to /tmp/.agent_prompt and references via $(cat ...).
      # This avoids all shell escaping issues with Shellwords.escape + newlines.
      if session.mode == "non_interactive" && session.initial_prompt.present?
        base_vars << "AGENT_PROMPT=#{session.initial_prompt}"
      end

      # Add agent-specific env vars from credential metadata (overrides session metadata)
      if input[:credential]&.metadata.present?
        agent_service = AgentCredentialsService.for(input[:agent_type])
        agent_env_vars = agent_service.adapter.env_vars_from_metadata(input[:credential].metadata)
        agent_env_vars.each { |k, v| base_vars << "#{k}=#{v}" if v.present? }
      end

      # Add session context env vars (Story 9.3)
      context_vars = SessionContextService.resolve_env_vars(session)
      context_vars.each { |k, v| base_vars << "#{k}=#{v}" }

      base_vars
    end

    def build_labels
      super.merge("palad.session_type" => "agent_session")
    end

    # == Lifecycle: before_exec ==
    # Load credentials into container

    def before_exec(context)
      container_ref = context[:container] || context[:container_id]
      container_id = runtime.container_identifier(container_ref)
      raise "Container not ready for before_exec" if container_id.blank?

      session = TerminalSession.find(input[:session_id])
      SessionContextService.assemble_session_context(
        container_ref, session, credential: input[:credential]
      )
    end

    # == Lifecycle: before_cleanup ==
    # Collect session artifacts (logs, outputs)

    def before_cleanup(context)
      container = context[:container]
      agent_service = AgentCredentialsService.for(input[:agent_type])

      artifacts = {}

      # 1. Collect session logs (if adapter supports it)
      if agent_service.adapter.respond_to?(:session_log_paths)
        agent_service.adapter.session_log_paths.each do |path|
          content = read_file_from_container(container, path)
          if content.present?
            artifacts["logs/#{File.basename(path)}"] = content
            Rails.logger.info("[AgentSession] Collected log: #{path}")
          end
        rescue StandardError => e
          Rails.logger.warn("[AgentSession] Failed to collect log #{path}: #{e.message}")
        end
      end

      # 2. Collect output artifacts (if adapter supports it)
      if agent_service.adapter.respond_to?(:output_artifact_paths)
        agent_service.adapter.output_artifact_paths.each do |path|
          # Try to list files if it's a pattern, otherwise read directly
          files = list_files_in_container(container, path)
          files.each do |file_path|
            content = read_file_from_container(container, file_path)
            if content.present?
              artifacts[file_path] = content
              Rails.logger.info("[AgentSession] Collected artifact: #{file_path}")
            end
          rescue StandardError => e
            Rails.logger.warn("[AgentSession] Failed to collect artifact #{file_path}: #{e.message}")
          end
        rescue StandardError => e
          Rails.logger.warn("[AgentSession] Failed to list files for #{path}: #{e.message}")
        end
      end

      context[:result] ||= {}
      context[:result][:artifacts] = artifacts
      context[:result][:artifacts_count] = artifacts.size

      Rails.logger.info("[AgentSession] Collected #{artifacts.size} artifacts")
    end

    protected

    # Ports to check for service readiness
    def services_ports
      [ 7681, 4040 ] # ttyd and file watcher
    end

    def session_type
      "agent_session"
    end

    def ttyd_command
      session = TerminalSession.find(input[:session_id])
      adapter = AgentCredentialsService.for(input[:agent_type]).adapter
      adapter.session_command(mode: session.mode, prompt: session.initial_prompt)
    end

    private

    # List files in container matching pattern
    #
    # @param container [Docker::Container] Container instance
    # @param path_pattern [String] Path or glob pattern
    # @return [Array<String>] List of file paths
    def list_files_in_container(container, path_pattern)
      # If it's a simple path (no wildcards), return it directly
      unless path_pattern.include?("*")
        return [ path_pattern ]
      end

      # Execute find to list matching files
      dir = File.dirname(path_pattern)
      name = File.basename(path_pattern)

      result = runtime.exec(
        container,
        [ "/bin/sh", "-c", "find #{dir} -name '#{name}' 2>/dev/null || true" ],
        stdout: true,
        stderr: true
      )

      stdout = result[0]
      exit_code = result[2]

      return [] unless exit_code.zero?

      stdout.join.split("\n").reject(&:blank?)
    rescue StandardError => e
      Rails.logger.warn("[AgentSession] Failed to list files: #{e.message}")
      []
    end
  end
end
