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
    POLL_INTERVAL = 5
    POLL_TIMEOUT = 82_800 # 23 hours

    def phase_config(phase)
      case phase
      when :pull_image  then { timeout: 600 }
      when :exec
        if non_interactive?
          { timeout: 85_800 }
        else
          { timeout: 300, await_signal: :container_finished, signal_timeout: 82_800 }
        end
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
      super.merge("palad.session_type" => "agent_session")
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

    # == exec(container_id:, **) → { websocket_url:, ..., agent_completed:?, exit_code:? } ==

    def exec(container_id:, **)
      result = super(container_id: container_id)
      result.delete(:watcher_url)

      session = TerminalSession.find(input[:session_id])
      return result if session.mode == "interactive"

      container = resolve_container(container_id)
      exit_code = poll_for_completion(container)

      meta = (session.metadata || {}).merge("exit_code" => exit_code)
      session.update!(metadata: meta)
      session.update!(error_message: "Agent exited with code #{exit_code}") unless exit_code.zero?

      result.merge(exit_code: exit_code, agent_completed: true)
    end

    # == before_cleanup(container_id:, **) → { logs_count:, outputs_count: } ==

    def before_cleanup(container_id: nil, **)
      return {} if container_id.blank?

      container = resolve_container(container_id)
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])

      logs_count, log_contents = collect_logs(container, session, agent_service)
      outputs_count = collect_outputs(container, session)
      collect_usage(session, agent_service, log_contents)

      Rails.logger.info("[AgentSession] Cleanup: #{logs_count} logs, #{outputs_count} outputs")
      { logs_count: logs_count, outputs_count: outputs_count }
    end

    protected

    def session_type = "agent_session"

    def ttyd_command
      session = TerminalSession.find(input[:session_id])
      AgentCredentialsService.for(input[:agent_type]).adapter
        .session_command(mode: session.mode, prompt: session.initial_prompt)
    end

    def services_ports
      non_interactive? ? [7681] : [7681, 8443]
    end

    private

    def non_interactive?
      session = TerminalSession.find(input[:session_id])
      session.mode == "non_interactive" && session.initial_prompt.present?
    end

    def poll_for_completion(container)
      deadline = Time.current + POLL_TIMEOUT

      loop do
        result = runtime.exec(
          container,
          ["/bin/sh", "-c", "cat /tmp/.agent_done 2>/dev/null"],
          stdout: true, stderr: true
        )

        return result[0].join.strip.to_i if result[2]&.zero?

        if Time.current > deadline
          Rails.logger.warn("[AgentSession] Polling timed out for session #{input[:session_id]}")
          return 124
        end

        sleep POLL_INTERVAL
      end
    end

    def collect_logs(container, session, agent_service)
      return [0, {}] unless agent_service.adapter.respond_to?(:session_log_paths)

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
      [count, contents]
    end

    def collect_outputs(container, session)
      output_dir = "/workspace/outputs"

      result = runtime.exec(
        container,
        ["/bin/sh", "-c", "find #{output_dir} -maxdepth 1 -type f 2>/dev/null || true"],
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

        tmpfile = Tempfile.new(["output-", File.extname(filename)])
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
      session.project.present? ? ["Project", session.project_id] : ["Company", session.user.company_id]
    end

    def collect_usage(session, agent_service, log_contents = {})
      return unless agent_service.adapter.respond_to?(:collect_usage)
      agent_service.adapter.collect_usage(session, log_contents)
    rescue StandardError => e
      Rails.logger.error("[AgentSession] Failed to collect usage: #{e.message}")
    end
  end
end
