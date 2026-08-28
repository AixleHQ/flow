# frozen_string_literal: true

module ContainerStrategies
  # AgentBaseStrategy
  # Shared base for agent container strategies (auth and session).
  #
  # Subclasses must implement:
  #   - session_type  — "auth_setup" or "agent_session"
  #   - ttyd_command  — command for the ttyd terminal
  #
  class AgentBaseStrategy < BaseStrategy
    VALID_AGENT_TYPES = %w[claude_code cursor_cli codex gemini_cli grok].freeze

    DEFAULT_AGENT_IMAGES = {
      "claude_code" => "aixle/claude-code:latest",
      "cursor_cli" => "aixle/cursor-cli:latest",
      "codex" => "aixle/codex:latest",
      "gemini_cli" => "aixle/gemini-cli:latest",
      "grok" => "aixle/grok:latest"
    }.freeze

    AUTH_COMMANDS = {
      "claude_code" => "claude",
      "cursor_cli" => "agent login",
      "codex" => "codex",
      "gemini_cli" => "gemini",
      # Device-code, not the default browser flow: nothing in the container can open a
      # browser, so this is the only Grok login that completes here — it prints a URL
      # and a code the user finishes on their own device.
      "grok" => "grok login --device-auth"
    }.freeze

    SESSION_COMMANDS = {
      "claude_code" => "claude",
      "cursor_cli" => "agent",
      "codex" => "codex --yolo",
      "gemini_cli" => "gemini --yolo",
      "grok" => "grok --yolo"
    }.freeze

    # == before_create_container ==
    # Returns container spec for agent containers.

    def before_create_container(**)
      validate_input!

      {
        container_name: "terminal-#{input[:route_token]}",
        image: resolve_image,
        env_vars: build_env_vars,
        labels: build_labels,
        host_config: build_host_config,
        exposed_ports: build_exposed_ports,
        cmd: build_cmd,
        working_dir: build_working_dir
      }
    end

    # == exec ==
    # Marks session ready and returns URLs for frontend.

    def exec(container_id:, **)
      container_ref = resolve_container(container_id)
      cid = runtime.container_identifier(container_ref)
      raise "Container not ready for exec" if cid.blank?

      route_token = input[:route_token]
      mark_session_ready(cid)

      {
        container_id: cid,
        container_name: "terminal-#{route_token}",
        websocket_url: "#{traefik_ws_base}/t/#{route_token}/tty/ws",
        watcher_url: "#{traefik_ws_base}/t/#{route_token}/fs",
        ide_url: "#{traefik_ws_base}/t/#{route_token}/ide/"
      }
    end

    # == Template methods ==

    def resolve_image
      configured_images = (Settings.agents&.images&.to_h || {}).transform_keys(&:to_s)
      configured_images.fetch(input[:agent_type], DEFAULT_AGENT_IMAGES.fetch(input[:agent_type]))
    end

    def session_type
      raise NotImplementedError, "#{self.class.name} must implement #session_type"
    end

    def ttyd_command
      raise NotImplementedError, "#{self.class.name} must implement #ttyd_command"
    end

    def build_env_vars
      session = TerminalSession.find(input[:session_id])
      agent_service = AgentCredentialsService.for(input[:agent_type])

      vscode_token = SecureRandom.hex(32)
      persist_vscode_token(session, vscode_token)

      env_vars = {
        "USER_ID" => input[:user_id].to_s,
        "AGENT_TYPE" => input[:agent_type],
        "SESSION_TYPE" => session_type,
        "SESSION_ID" => input[:session_id].to_s,
        "TTYD_PORT" => "7681",
        "WATCHER_PORT" => "4040",
        "ROUTE_TOKEN" => input[:route_token],
        "VSCODE_TOKEN" => vscode_token,
        "TTYD_CMD" => ttyd_command,
        "HOME_DIR" => agent_service.home_dir,
        "AUTH_WATCH_PATH" => agent_service.auth_watch_path,
        "AUTH_REQUIRED_KEYS" => agent_service.adapter.auth_required_keys.join(","),
        "TMUX_TMPDIR" => "/dev/shm/tmux"
      }

      env_vars.merge!(agent_service.adapter.default_env_vars(session))
      env_vars.merge!(agent_service.adapter.env_vars_from_metadata(session.metadata)) if session.metadata.present?
      super + env_vars.compact.map { |k, v| "#{k}=#{v}" }
    end

    # Send one command into the container's `agent` tmux session once its shell prompt
    # is ready. Used to launch the CLI AFTER before_exec seeds credentials (so it starts
    # authenticated), rather than at container start via the entrypoint's TTYD_CMD.
    def send_tmux_command(container, cmd)
      send_tmux_sequence(container, [ cmd ])
    end

    # Send a sequence of commands: wait for the shell prompt, send the first, then send
    # each subsequent one after a short delay (e.g. launch the CLI, then drive a slash
    # command once it is up). Which commands to send is the caller's concern.
    def send_tmux_sequence(container, commands)
      return if commands.blank?

      first, *rest = commands
      script = +"for i in $(seq 1 30); do tmux capture-pane -t agent -p 2>/dev/null | grep -q '\\$' && break; sleep 0.2; done; "
      script << "tmux send-keys -t agent #{Shellwords.shellescape(first)} Enter; "
      rest.each { |cmd| script << "sleep 5; tmux send-keys -t agent #{Shellwords.shellescape(cmd)} Enter; " }
      runtime.exec(container, [ "sh", "-c", script ])
    end

    def build_labels
      route_token = input[:route_token]
      router_name = "terminal-#{route_token}"
      base_labels.merge(traefik_labels(route_token, router_name))
    end

    def build_host_config
      base_host_config
    end

    def build_exposed_ports
      { "7681/tcp" => {}, "4040/tcp" => {}, "8443/tcp" => {} }
    end

    protected

    def services_ports
      [ 7681, 4040 ]
    end

    def traefik_ws_base
      Settings.traefik.ws_base
    end

    def mark_session_ready(container_id)
      session = TerminalSession.find(input[:session_id])
      session.container_id = container_id
      session.mark_ready! if session.may_mark_ready?
    rescue StandardError => e
      Rails.logger.warn("[#{strategy_name}] Failed to mark session ready: #{e.message}")
    end

    def upsert_env_var(env_vars, key, value)
      return if value.blank?

      env_vars.reject! { |entry| entry.start_with?("#{key}=") }
      env_vars << "#{key}=#{value}"
    end

    private

    def validate_input!
      raise ArgumentError, "user_id is required" unless input[:user_id].present?
      raise ArgumentError, "agent_type is required" unless input[:agent_type].present?
      raise ArgumentError, "session_id is required" unless input[:session_id].present?
      raise ArgumentError, "route_token is required" unless input[:route_token].present?

      unless VALID_AGENT_TYPES.include?(input[:agent_type])
        raise ArgumentError, "Invalid agent_type: #{input[:agent_type]}"
      end
    end

    def persist_vscode_token(session, token)
      meta = session.metadata || {}
      meta["vscode_token"] = token
      session.update_column(:metadata, meta)
    end

    def base_labels
      {
        "aixle.session_type" => session_type,
        "aixle.agent_type" => input[:agent_type],
        "aixle.user_id" => input[:user_id].to_s,
        "aixle.session_id" => input[:session_id].to_s,
        "aixle.ttyd_port" => "7681"
      }
    end

    # =================================================================
    # Credential extraction (shared by auth + session strategies)
    # =================================================================

    # Read the agent's auth file(s) from the container.
    # @return [Hash<String, String>] path => content (only present files)
    def extract_auth_files(container, agent_service)
      paths = if agent_service.adapter.respond_to?(:auth_file_paths)
                agent_service.adapter.auth_file_paths
      else
                [ agent_service.config_path ]
      end

      paths.each_with_object({}) do |path, files|
        content = read_file_from_container(container, path)
        files[path] = content if content.present?
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Failed to extract #{path}: #{e.message}")
      end
    end

    # True only when one of the auth files actually contains a real credential/token.
    # Guards against persisting a credential when the file merely exists (e.g. Claude
    # Code always writes ~/.claude.json on startup, even before login completes).
    def auth_files_complete?(auth_files, agent_service)
      auth_files.any? { |_path, content| content.present? && agent_service.auth_complete?(content) }
    end

    # Build the minimal credential hash to persist from collected auth files.
    # Uses the adapter's #extract_credentials (a clean slice of the needed keys)
    # rather than storing whole config blobs, so credentials stay tidy and a
    # re-auth replaces them with no leftover fields from a previous login.
    def build_credentials_from_files(auth_files, adapter)
      config_data = {}

      auth_files.each do |path, content|
        basename = File.basename(path)

        # Gemini: API key lives in an encrypted file — decrypt instead of slicing.
        if basename == "gemini-credentials.json" && adapter.respond_to?(:decrypt_credentials_file)
          api_key = adapter.decrypt_credentials_file(content, extract_container_hostname)
          config_data["api_key"] = api_key if api_key
          next
        end

        # settings.json carries no secrets we persist (auth method marker only). An adapter
        # may still want the non-secret choices recorded there — Claude Code's Bedrock
        # wizard writes its region and model pins here and nowhere else, and those pins are
        # what keep the next session off Opus-rate billing.
        if basename == "settings.json"
          if adapter.respond_to?(:extract_settings_config)
            config_data.merge!(adapter.extract_settings_config(content))
          end
          next
        end

        config_data.merge!(adapter.extract_credentials(content))
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Failed to process #{path}: #{e.message}")
      end

      config_data
    end

    def extract_container_hostname
      session = TerminalSession.find(input[:session_id])
      container = resolve_container(session.container_id)
      result = runtime.exec(container, [ "hostname" ])
      result[0].join.strip
    rescue StandardError
      ""
    end

    def traefik_labels(route_token, router_name)
      labels = {
        "traefik.enable" => "true",
        "traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/t/#{route_token}/tty`)",
        "traefik.http.routers.#{router_name}-tty.middlewares" => "terminal-auth,#{router_name}-tty-strip",
        "traefik.http.middlewares.#{router_name}-tty-strip.stripprefix.prefixes" => "/t/#{route_token}/tty",
        "traefik.http.routers.#{router_name}-tty.service" => "#{router_name}-tty",
        "traefik.http.services.#{router_name}-tty.loadbalancer.server.port" => "7681",
        "traefik.http.routers.#{router_name}-fs.rule" => "PathPrefix(`/t/#{route_token}/fs`)",
        "traefik.http.routers.#{router_name}-fs.middlewares" => "terminal-cors,terminal-auth,#{router_name}-fs-strip",
        "traefik.http.middlewares.#{router_name}-fs-strip.stripprefix.prefixes" => "/t/#{route_token}/fs",
        "traefik.http.routers.#{router_name}-fs.service" => "#{router_name}-fs",
        "traefik.http.services.#{router_name}-fs.loadbalancer.server.port" => "4040",
        "traefik.http.routers.#{router_name}-ide.rule" => "PathPrefix(`/t/#{route_token}/ide`)",
        "traefik.http.routers.#{router_name}-ide.middlewares" => "terminal-auth",
        "traefik.http.routers.#{router_name}-ide.service" => "#{router_name}-ide",
        "traefik.http.services.#{router_name}-ide.loadbalancer.server.port" => "8443"
      }

      labels
    end
  end
end
