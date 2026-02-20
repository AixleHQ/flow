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
        agent_env_vars.each { |k, v| upsert_env_var(base_vars, k, v) }
      end

      # Add session context env vars (Story 9.3)
      context_vars = SessionContextService.resolve_env_vars(session)
      context_vars.each { |k, v| upsert_env_var(base_vars, k, v) }

      base_vars
    end

    def build_labels
      super.merge("palad.session_type" => "agent_session")
    end

    # == Lifecycle: exec ==
    # Interactive: return URLs immediately, workflow waits for user signal.
    # Non-interactive: block until agent command finishes (like tool execution).

    def exec(context)
      super(context)
      context[:result].delete(:watcher_url)

      session = TerminalSession.find(input[:session_id])
      return if session.mode == "interactive"

      exit_code = poll_for_completion(context[:container])
      context[:result][:exit_code] = exit_code
      context[:result][:agent_completed] = true

      meta = (session.metadata || {}).merge("exit_code" => exit_code)
      session.update!(metadata: meta)
      session.update!(error_message: "Agent exited with code #{exit_code}") unless exit_code.zero?
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
    # Collect session logs as SessionLog records, outputs as Assets, and usage statistics

    def before_cleanup(context)
      container = context[:container]
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])

      logs_count, log_contents = collect_logs(container, session, agent_service)
      outputs_count = collect_outputs(container, session)
      collect_usage(session, agent_service, log_contents)

      context[:result] ||= {}
      context[:result][:logs_count] = logs_count
      context[:result][:outputs_count] = outputs_count

      mark_session_collected

      Rails.logger.info("[AgentSession] Cleanup: #{logs_count} logs, #{outputs_count} outputs")
    end

    protected

    # Ports to check for service readiness
    # OpenVSCode Server (8443) is only started for interactive sessions (no AGENT_PROMPT)
    def services_ports
      session = TerminalSession.find(input[:session_id])
      if session.mode == "non_interactive" && session.initial_prompt.present?
        [ 7681 ]
      else
        [ 7681, 8443 ]
      end
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

    def collect_logs(container, session, agent_service)
      return [ 0, {} ] unless agent_service.adapter.respond_to?(:session_log_paths)

      count = 0
      contents = {}
      agent_service.adapter.session_log_paths.each do |path|
        content = read_file_from_container(container, path)
        next if content.blank?

        filename = File.basename(path)
        contents["logs/#{filename}"] = content

        io = StringIO.new(content)
        io.define_singleton_method(:original_filename) { filename }

        SessionLog.create!(
          terminal_session: session,
          name: filename,
          file: io,
          file_size: content.bytesize,
          content_type: Marcel::MimeType.for(name: filename, extension: File.extname(filename))
        )
        count += 1
        Rails.logger.info("[AgentSession] Collected log: #{path} (#{content.bytesize} bytes)")
      rescue StandardError => e
        Rails.logger.warn("[AgentSession] Failed to collect log #{path}: #{e.message}")
      end
      [ count, contents ]
    end

    def collect_outputs(container, session)
      output_dir = "/workspace/outputs"

      result = runtime.exec(
        container,
        [ "/bin/sh", "-c", "find #{output_dir} -maxdepth 1 -type f 2>/dev/null || true" ],
        stdout: true, stderr: true
      )
      return 0 unless result[2].zero?

      files = result[0].join.split("\n").reject(&:blank?)
      return 0 if files.empty?

      scope_type, scope_id = resolve_output_scope(session)
      count = 0

      files.each do |file_path|
        filename = File.basename(file_path)
        content = read_file_from_container(container, file_path)
        next if content.blank?

        tmpfile = Tempfile.new([ "output-", File.extname(filename) ])
        tmpfile.binmode
        tmpfile.write(content)
        tmpfile.rewind
        tmpfile.define_singleton_method(:original_filename) { filename }

        asset = Asset.create!(
          name: filename,
          folder: "session-#{session.id}",
          scope_type: scope_type,
          scope_id: scope_id,
          created_by: session.user,
          terminal_session: session,
          status: "pending_review"
        )

        AssetVersion.create!(
          asset: asset,
          uploaded_by: session.user,
          source: :session,
          file: tmpfile
        )

        count += 1
        Rails.logger.info("[AgentSession] Collected output: #{filename}")
      rescue StandardError => e
        Rails.logger.warn("[AgentSession] Failed to collect output #{file_path}: #{e.message}")
      ensure
        tmpfile&.close!
      end

      count
    rescue StandardError => e
      Rails.logger.warn("[AgentSession] Failed to list outputs: #{e.message}")
      0
    end

    def resolve_output_scope(session)
      if session.project.present?
        [ "Project", session.project_id ]
      else
        [ "Company", session.user.company_id ]
      end
    end

    def collect_usage(session, agent_service, log_contents = {})
      return unless agent_service.adapter.respond_to?(:collect_usage)

      agent_service.adapter.collect_usage(session, log_contents)
      Rails.logger.info("[AgentSession] Usage statistics collected for session #{session.id}")
    rescue StandardError => e
      Rails.logger.error("[AgentSession] Failed to collect usage: #{e.message}")
    end

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

    # Poll container for /tmp/.agent_done marker file.
    # Written by run_agent.sh when the agent command exits.
    POLL_INTERVAL = 5
    POLL_TIMEOUT = 82_800 # 23 hours

    def poll_for_completion(container)
      deadline = Time.current + POLL_TIMEOUT

      loop do
        result = runtime.exec(
          container,
          [ "/bin/sh", "-c", "cat /tmp/.agent_done 2>/dev/null" ],
          stdout: true, stderr: true
        )

        if result[2]&.zero?
          return result[0].join.strip.to_i
        end

        if Time.current > deadline
          Rails.logger.warn("[AgentSession] Polling timed out for session #{input[:session_id]}")
          return 124
        end

        sleep POLL_INTERVAL
      end
    end

    def upsert_env_var(env_vars, key, value)
      return if value.blank?

      env_vars.reject! { |entry| entry.start_with?("#{key}=") }
      env_vars << "#{key}=#{value}"
    end
  end
end
