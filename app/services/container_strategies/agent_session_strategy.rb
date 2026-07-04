# frozen_string_literal: true

module ContainerStrategies
  # AgentSessionStrategy
  # Strategy for agent session containers with pre-loaded credentials.
  #
  # Session-specific:
  #   - build_env_vars: credential/context env vars, AGENT_PROMPT for non-interactive
  #   - before_exec: loads credentials via SessionContextService
  #   - exec: interactive → URLs; non-interactive → polls for completion
  #   - before_cleanup: collects logs, outputs, usage
  #   - phase_config: non-interactive long timeout, interactive awaits signal
  #
  class AgentSessionStrategy < AgentBaseStrategy
    def phase_config(phase)
      case phase
      when :pull_image  then { timeout: 600 }
      when :exec        then { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
      when :cleanup     then { timeout: 120, always: true, retry: { max_attempts: 2, interval: 5 } }
      else                   { timeout: 300 }
      end
    end

    def build_env_vars
      env_vars_list = super

      session = TerminalSession.find(input[:session_id])

      if session.mode == "non_interactive" && session.initial_prompt.present?
        env_vars_list << "AGENT_PROMPT=#{session.initial_prompt}"
      end

      if input[:credential]&.metadata.present?
        agent_service = AgentCredentialsService.for(input[:agent_type])
        agent_service.adapter.env_vars_from_metadata(input[:credential].metadata)
          .each { |k, v| upsert_env_var(env_vars_list, k, v) }
      end

      SessionContextService.resolve_env_vars(session)
        .each { |k, v| upsert_env_var(env_vars_list, k, v) }

      env_vars_list
    end

    def build_labels
      super.merge("aixle.session_type" => "agent_session")
    end

    # == before_exec(container_id:, **) → {} ==

    def before_exec(container_id:, **)
      container = resolve_container(container_id)
      cid = runtime.container_identifier(container)
      raise "Container not ready for before_exec" if cid.blank?

      session = TerminalSession.find(input[:session_id])
      SessionContextService.assemble_session_context(container, session, credential: input[:credential])
      {}
    end

    # == exec(container_id:, **) → { websocket_url:, ... } ==

    def exec(container_id:, **)
      container = resolve_container(container_id)
      launch_agent_in_tmux(container)

      result = super(container_id: container_id)
      result.delete(:watcher_url)
      result
    end

    # == before_cleanup(container_id:, **) → { logs_count:, outputs_count: } ==

    def before_cleanup(container_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])

      logs_count, log_contents = collect_logs(container, session, agent_service)
      logs_count += collect_terminal_output(container, session)
      outputs_count = collect_outputs(container, session)
      collect_usage(session, agent_service, log_contents)
      persist_refreshed_credentials(container, session, agent_service)
      IntegrationCleanupService.release_session_locks!(session)

      Rails.logger.info("[AgentSession] Cleanup: #{logs_count} logs, #{outputs_count} outputs")
      { logs_count: logs_count, outputs_count: outputs_count }
    end

    protected

    def session_type = "agent_session"

    def ttyd_command
      "bash"
    end

    def services_ports
      [ 7681, 8443 ]
    end

    def resolve_model(session)
      return session.requested_model if session.requested_model.present?

      # Fall back to user's default model for this runtime
      credential = session.user.agent_credentials.find_by(agent_type: session.agent_type)
      credential&.metadata&.dig("default_model")
    end

    private

    def launch_agent_in_tmux(container)
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])
      cmd = agent_service.adapter.session_command(mode: session.mode, prompt: session.initial_prompt, model: resolve_model(session))

      tmux_cmd = if session.mode == "non_interactive" && session.initial_prompt.present?
        "#{cmd} \"$AGENT_PROMPT\""
      else
        cmd
      end

      runtime.exec(container, [ "sh", "-c", "for i in $(seq 1 30); do tmux capture-pane -t agent -p 2>/dev/null | grep -q '\\$' && break; sleep 0.2; done; tmux send-keys -t agent '#{tmux_cmd}' Enter" ])
      Rails.logger.info("[AgentSession] Launched agent in tmux: #{cmd}")
    end

    def collect_terminal_output(container, session)
      runtime.exec(container, [
        "sh", "-c",
        "tmux capture-pane -t agent -p -S - > /tmp/terminal_output.log 2>/dev/null"
      ])

      content = read_file_from_container(container, "/tmp/terminal_output.log")
      return 0 if content.blank?

      io = StringIO.new(content)
      io.define_singleton_method(:original_filename) { "terminal_output.log" }

      SessionLog.create!(
        terminal_session: session,
        name: "terminal_output.log",
        file: io,
        file_size: content.bytesize,
        content_type: "text/plain"
      )
      1
    rescue StandardError => e
      Rails.logger.warn("[AgentSession] Failed to collect terminal output: #{e.message}")
      0
    end

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
          name: filename, folder: "session-#{session.id}",
          scope_type: scope_type, scope_id: scope_id,
          created_by: session.user, terminal_session: session,
          status: "pending_review"
        )
        AssetVersion.create!(asset: asset, uploaded_by: session.user, source: :session, file: tmpfile)
        count += 1
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
      session.project.present? ? [ "Project", session.project_id ] : [ "Company", session.user.company_id ]
    end

    def collect_usage(session, agent_service, log_contents = {})
      return unless agent_service.adapter.respond_to?(:collect_usage)
      agent_service.adapter.collect_usage(session, log_contents)
    rescue StandardError => e
      Rails.logger.error("[AgentSession] Failed to collect usage: #{e.message}")
    end

    # Agents (e.g. Claude Code) refresh their access/refresh tokens during a
    # session. Those refreshed tokens live only in the container's config files;
    # without this, the next session reloads the old (possibly expired) token.
    # Re-extract the auth files and update the stored credential when the token
    # material actually changed. Only updates an existing credential — never
    # creates one from a session.
    def persist_refreshed_credentials(container, session, agent_service)
      auth_files = extract_auth_files(container, agent_service)
      return unless auth_files_complete?(auth_files, agent_service)

      config_data = build_credentials_from_files(auth_files, agent_service.adapter)
      return if config_data.blank?

      credential = session.user.agent_credentials.find_by(agent_type: input[:agent_type])
      return unless credential
      return if credential.config_data == config_data # cheap pre-check, avoids locking on no-op

      adapter = agent_service.adapter
      # Lock the row so concurrent sessions can't race the read-merge-write. The adapter
      # merges per token block and refuses to downgrade a newer stored token to an older
      # one — refresh-token rotation means a late-cleaning session could otherwise persist
      # an already-revoked token or wipe a token block (e.g. designOauth) it never touched.
      credential.with_lock do
        current = credential.config_data
        merged = adapter.merge_refreshed_credentials(current, config_data)
        next if merged == current

        AgentCredential.from_artifacts(session.user_id, input[:agent_type], merged)
        Rails.logger.info("[AgentSession] Persisted refreshed #{input[:agent_type]} credentials for user #{session.user_id}")
      end
    rescue StandardError => e
      Rails.logger.warn("[AgentSession] Failed to persist refreshed credentials: #{e.message}")
    end
  end
end
