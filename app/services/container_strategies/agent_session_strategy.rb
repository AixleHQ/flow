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
    SESSION_REFRESH_THRESHOLD = 60.minutes

    class InvalidGrantError < StandardError; end

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

      # No config-item env injection here, deliberately: a session reaches its
      # attached config items through the `get_config_item` MCP tool and nowhere
      # else, so there is exactly one channel to reason about (and exactly one
      # that writes an audit row). See
      # docs/implementation-artifacts/spec-session-config-item-access.md.
      scrub_conflicting_auth_env(env_vars_list)
    end

    # Last step, after every other source has had its say: drop env the active provider
    # config would silently lose to. A leftover ANTHROPIC_API_KEY shadows a Bedrock
    # connection, and Claude Code hides Bedrock errors — so the symptom is an agent that
    # simply does not answer. The corporate runbook works around exactly this by
    # scrubbing stray keys before launch.
    def scrub_conflicting_auth_env(env_vars_list)
      credential = input[:credential]
      return env_vars_list if credential.nil?

      adapter = AgentCredentialsService.for(input[:agent_type]).adapter
      conflicting = adapter.conflicting_env_keys(credential.config_data)
      return env_vars_list if conflicting.empty?

      env_vars_list.reject do |entry|
        key = entry.to_s.split("=", 2).first
        conflicting.include?(key).tap do |dropped|
          Rails.logger.info("[AgentSession] dropped #{key}: conflicts with the active provider") if dropped
        end
      end
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
      credential = input[:credential]
      refresh_credential_if_expiring(credential, session: session)
      SessionContextService.assemble_session_context(container, session, credential: credential)
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

      # Fall back to the default model chosen on THIS session's company credential. The
      # pin is per credential, and a credential is per company — a model pinned against
      # another company's Bedrock account does not exist here.
      credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: session.agent_type)
      credential&.default_model
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

      send_tmux_command(container, tmux_cmd)
      Rails.logger.info("[AgentSession] Launched agent in tmux: #{cmd}")
    end

    # Built once per cleanup: resolving the session's attached secrets decrypts
    # rows, and both collectors run back to back over the same session.
    def secret_redactor(session)
      @secret_redactor ||= Sessions::SecretRedactor.for_session(session)
    end

    def collect_terminal_output(container, session)
      # The file is populated live by the `agent` pane's tmux pipe-pane, set up in
      # docker/base/entrypoint.sh at container start (`tee -a /tmp/terminal_output.log`),
      # so it already holds the raw ANSI stream — no capture-pane snapshot needed.
      content = read_file_from_container(container, "/tmp/terminal_output.log")
      return 0 if content.blank?

      # Anything the agent echoed — a value it read through get_config_item, most
      # of all — is in this stream verbatim. Scrub before it is persisted and
      # replayed in the UI.
      content = secret_redactor(session).call(content)

      io = StringIO.new(content)
      io.define_singleton_method(:original_filename) { "terminal_output.log" }

      SessionLog.create!(
        terminal_session: session,
        name: "terminal_output.log",
        file: io,
        file_size: content.bytesize,
        content_type: "text/plain; charset=utf-8"
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
      redactor = secret_redactor(session)
      agent_service.adapter.session_log_paths.each do |path|
        content = read_file_from_container(container, path)
        next if content.blank?

        # Covers /var/log/mitm/http.log, which holds the FULL provider request
        # bodies — so every value the agent read is in there, having travelled to
        # the model as part of the conversation.
        content = redactor.call(content)

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

      # Recurse: agents organize outputs into subdirs (e.g. outputs/presentation/index.html).
      # A -maxdepth 1 scan would silently miss all of them. The relative path (not the bare
      # basename) becomes the asset name so nested files keep their structure and distinct
      # files that share a basename across subdirs don't collide on the name uniqueness index.
      result = runtime.exec(
        container,
        [ "/bin/sh", "-c", "find #{output_dir} -type f 2>/dev/null || true" ],
        stdout: true, stderr: true
      )
      return 0 unless result[2].zero?

      files = result[0].join.split("\n").reject(&:blank?)
      return 0 if files.empty?

      scope_type, scope_id = resolve_output_scope(session)
      count = 0

      files.each do |file_path|
        relative = file_path.sub("#{output_dir}/", "")
        filename = File.basename(relative)
        content = read_file_from_container(container, file_path)
        if content.blank?
          # A dropped output used to leave no trace at all — the asset simply never
          # appeared. Log it, so an unreadable file is distinguishable from an empty one.
          Rails.logger.warn("[AgentSession] Skipped output #{file_path}: #{content.nil? ? 'unreadable' : 'empty'}")
          next
        end

        tmpfile = Tempfile.new([ "output-", File.extname(filename) ])
        tmpfile.binmode
        tmpfile.write(content)
        tmpfile.rewind
        tmpfile.define_singleton_method(:original_filename) { filename }

        asset = Asset.create!(
          name: relative, folder: "session-#{session.id}",
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

    # Output scope follows the session's project; project-less sessions fall
    # back to the user's first active membership's company. A user with zero
    # active memberships has no valid scope — raise (collect_outputs logs and
    # skips) instead of creating assets with a nil scope_id.
    def resolve_output_scope(session)
      return [ "Project", session.project_id ] if session.project.present?

      company_id = session.user.company_memberships.active.default_order.pick(:company_id)
      if company_id.nil?
        raise "cannot resolve output scope: user #{session.user_id} has no active membership (session #{session.id})"
      end

      [ "Company", company_id ]
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
    def refresh_credential_if_expiring(credential, session: nil)
      return unless credential

      expires_at = credential.expires_at

      if expires_at
        remaining_sec = expires_at - Time.current
        if remaining_sec >= 0
          Rails.logger.info("[AgentSession] Token expires_at=#{expires_at.iso8601} (#{(remaining_sec / 60).round}m remaining) for credential #{credential.id}")
        else
          Rails.logger.info("[AgentSession] Token expires_at=#{expires_at.iso8601} (expired #{(-remaining_sec / 60).round}m ago) for credential #{credential.id}")
        end

        if expires_at <= SESSION_REFRESH_THRESHOLD.from_now
          adapter = AgentCredentialsService.for(credential.agent_type).adapter
          result = adapter.refresh!(credential)
          Rails.logger.info("[AgentSession] Pre-session token refresh credential=#{credential.id} status=#{result[:status]} detail=#{result[:detail].inspect}")

          if credential.agent_type == "claude_code" && result[:detail].to_s.include?("invalid_grant")
            message = "Your Claude Code login has expired and could not be refreshed automatically. " \
                      "Go to your profile settings and sign in again."
            SessionService.fail_session(session: session, error_message: message) if session
            raise InvalidGrantError, message
          end

          begin
            credential.reload
          rescue ActiveRecord::ActiveRecordError => e
            Rails.logger.error("[AgentSession] Refresh succeeded but credential.reload failed for #{credential.id}: #{e.class}: #{e.message}")
          end
        end
      else
        Rails.logger.info("[AgentSession] Token has no expiry (API key or Bedrock) for credential #{credential.id}")
      end
    rescue InvalidGrantError
      raise
    rescue ArgumentError
      raise
    rescue StandardError => e
      Rails.logger.error("[AgentSession] Pre-session credential refresh failed for #{credential.id}: #{e.class}: #{e.message}")
    end

    def persist_refreshed_credentials(container, session, agent_service)
      auth_files = extract_auth_files(container, agent_service)
      return unless auth_files_complete?(auth_files, agent_service)

      config_data = build_credentials_from_files(auth_files, agent_service.adapter)
      return if config_data.blank?

      # This session's company's credential — the same row the write below targets.
      credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: input[:agent_type])
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

        AgentCredential.from_artifacts(session.user_id, SessionCompany.company_id_for(session), input[:agent_type], merged)
        Rails.logger.info("[AgentSession] Persisted refreshed #{input[:agent_type]} credentials for user #{session.user_id}")
      end
    rescue StandardError => e
      Rails.logger.warn("[AgentSession] Failed to persist refreshed credentials: #{e.message}")
    end
  end
end
