# frozen_string_literal: true

module ContainerStrategies
  # AgentAuthStrategy
  # Strategy for starting agent authentication containers
  #
  # Creates a container with ttyd terminal for interactive agent authentication.
  # User completes auth via web terminal, then credentials are extracted.
  #
  # Lifecycle phases:
  #   - before_create: Build container config with Traefik labels
  #   - create: Create container with tmpfs mounts
  #   - start: Start container, wait for health
  #   - exec: Return URLs for frontend (no blocking execution)
  #   - before_cleanup: Extract auth files from container
  #   - cleanup: Stop and remove container
  #
  # Input:
  #   - user_id: User ID
  #   - agent_type: claude_code | cursor_cli | codex | gemini_cli
  #   - session_id: TerminalSession ID
  #   - route_token: Random token for URL routing
  #
  # @example
  #   strategy = AgentAuthStrategy.new(
  #     user_id: 1,
  #     agent_type: "claude_code",
  #     session_id: 123,
  #     route_token: "abc123"
  #   )
  #   result = ContainerService.execute(strategy: strategy, input: strategy.input)
  #
  class AgentAuthStrategy < BaseStrategy
    VALID_AGENT_TYPES = %w[claude_code cursor_cli codex gemini_cli].freeze

    AGENT_IMAGES = {
      "claude_code" => "palad/claude-code:latest",
      "cursor_cli" => "palad/cursor-cli:latest",
      "codex" => "palad/codex:latest",
      "gemini_cli" => "palad/gemini-cli:latest"
    }.freeze

    AUTH_COMMANDS = {
      "claude_code" => "claude",
      "cursor_cli" => "agent login",
      "codex" => "codex",
      "gemini_cli" => "gemini"
    }.freeze

    SESSION_COMMANDS = {
      "claude_code" => "claude",
      "cursor_cli" => "agent",
      "codex" => "codex --yolo",
      "gemini_cli" => "gemini --yolo"
    }.freeze

    # == Lifecycle: before_create ==

    def before_create(context)
      validate_input!
      context[:container_name] = "terminal-#{input[:route_token]}"
      super(context)
    end

    # == Template Methods ==

    def resolve_image
      AGENT_IMAGES.fetch(input[:agent_type])
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
        "AUTH_REQUIRED_KEYS" => agent_service.adapter.auth_required_keys.join(",")
      }

      # Add adapter defaults (e.g., telemetry/OTEL settings)
      env_vars.merge!(agent_service.adapter.default_env_vars(session))

      # Add agent-specific env vars from session metadata
      if session.metadata.present?
        env_vars.merge!(agent_service.adapter.env_vars_from_metadata(session.metadata))
      end

      env_vars.compact.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      route_token = input[:route_token]
      router_name = "terminal-#{route_token}"

      base_labels.merge(traefik_labels(route_token, router_name))
    end

    def build_host_config
      agent_service = AgentCredentialsService.for(input[:agent_type])

      base_host_config.merge(
        "Tmpfs" => build_tmpfs_mounts(
          agent_service.adapter.tmpfs_paths,
          agent_service.adapter.tmpfs_uid
        )
      )
    end

    def build_exposed_ports
      {
        "7681/tcp" => {},  # ttyd
        "4040/tcp" => {},  # watcher
        "8443/tcp" => {}   # OpenVSCode Server
      }
    end

    # == Lifecycle: exec ==
    # Return URLs for frontend (no blocking execution)

    def exec(context)
      route_token = input[:route_token]
      container_ref = context[:container] || context[:container_id]
      container_id = runtime.container_identifier(container_ref)

      # Mark session running — at this point container is started, ports are healthy,
      # and credentials are loaded (before_exec done). Safe for frontend to connect.
      mark_session_running(container_id)
      raise "Container not ready for exec" if container_id.blank?

      websocket_url = "#{traefik_ws_base}/t/#{route_token}/tty/ws"
      watcher_url = "#{traefik_ws_base}/t/#{route_token}/fs"
      ide_url = "#{traefik_ws_base}/t/#{route_token}/ide/"

      context[:result] = {
        container_id: container_id,
        container_name: "terminal-#{route_token}",
        websocket_url: websocket_url,
        watcher_url: watcher_url,
        ide_url: ide_url
      }

      Rails.logger.info("[AgentAuth] Container ready. TTY: #{websocket_url}, IDE: #{ide_url}")
    end

    # == Lifecycle: before_cleanup ==
    # Extract auth files from container and save credentials

    def before_cleanup(context)
      container = context[:container]
      session = context[:session]
      agent_service = AgentCredentialsService.for(input[:agent_type])

      # Step 1: Extract auth files
      auth_files = extract_auth_files(container, agent_service)

      context[:result] ||= {}
      context[:result][:auth_files] = auth_files
      context[:result][:auth_completed] = auth_files.any?

      # Step 2: Save credentials if we have auth files
      if auth_files.any? && session.present?
        credential = save_credentials(session, auth_files)
        context[:result][:credential_id] = credential.id
        Rails.logger.info("[AgentAuth] Credential saved: #{credential.id}")
      end

      Rails.logger.info("[AgentAuth] before_cleanup completed: #{auth_files.size} files")
    end

    protected

    # Ports to check for service readiness
    def services_ports
      [ 7681, 4040 ] # ttyd and file watcher
    end

    def session_type
      "auth_setup"
    end

    def ttyd_command
      AUTH_COMMANDS.fetch(input[:agent_type])
    end

    def traefik_ws_base
      Settings.traefik.ws_base
    end

    def traefik_http_base
      Settings.traefik.http_base
    end

    def mcp_server_url
      ENV.fetch("MCP_SERVER_URL", "http://web:4002/action_mcp")
    end

    private

    def mark_session_running(container_id)
      session = TerminalSession.find(input[:session_id])
      session.update!(container_id: container_id)
      session.mark_running! if session.may_mark_running?
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to mark session running: #{e.message}")
    end

    def mark_session_failed(error_message)
      session = TerminalSession.find(input[:session_id])
      session.update(error_message: error_message)
      session.fail! if session.may_fail?
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to mark session failed: #{e.message}")
    end

    def mark_session_collected
      session = TerminalSession.find(input[:session_id])
      session.update(container_id: nil)
      session.collect! if session.may_collect?
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to mark session collected: #{e.message}")
    end

    def extract_auth_files(container, agent_service)
      auth_files = {}

      if agent_service.adapter.respond_to?(:auth_file_paths)
        agent_service.adapter.auth_file_paths.each do |path|
          content = read_file_from_container(container, path)
          if content.present?
            auth_files[path] = content
            Rails.logger.info("[AgentAuth] Extracted: #{path} (#{content.bytesize} bytes)")
          end
        rescue StandardError => e
          Rails.logger.warn("[AgentAuth] Failed to extract #{path}: #{e.message}")
        end
      else
        # Fallback: extract main config file
        content = read_file_from_container(container, agent_service.config_path)
        if content.present?
          auth_files[agent_service.config_path] = content
          Rails.logger.info("[AgentAuth] Extracted config: #{agent_service.config_path}")
        end
      end

      auth_files
    end

    def save_credentials(session, auth_files)
      config_data = parse_auth_files(auth_files)
      AgentCredential.from_artifacts(session.user_id, input[:agent_type], config_data)
    end

    def parse_auth_files(auth_files)
      config_data = {}

      auth_files.each do |path, content|
        parsed = JSON.parse(content)
        config_data.merge!(parsed)
      rescue JSON::ParserError
        # Store raw content under path key if not JSON
        config_data[path] = content
      end

      config_data
    end

    def persist_vscode_token(session, token)
      meta = session.metadata || {}
      meta["vscode_token"] = token
      session.update_column(:metadata, meta)
    end

    def validate_input!
      raise ArgumentError, "user_id is required" unless input[:user_id].present?
      raise ArgumentError, "agent_type is required" unless input[:agent_type].present?
      raise ArgumentError, "session_id is required" unless input[:session_id].present?
      raise ArgumentError, "route_token is required" unless input[:route_token].present?

      unless VALID_AGENT_TYPES.include?(input[:agent_type])
        raise ArgumentError, "Invalid agent_type: #{input[:agent_type]}"
      end
    end

    def base_labels
      {
        "palad.session_type" => session_type,
        "palad.agent_type" => input[:agent_type],
        "palad.user_id" => input[:user_id].to_s,
        "palad.session_id" => input[:session_id].to_s,
        "palad.ttyd_port" => "7681"
      }
    end

    def traefik_labels(route_token, router_name)
      {
        # Enable Traefik
        "traefik.enable" => "true",

        # TTY router (ttyd terminal)
        "traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/t/#{route_token}/tty`)",
        "traefik.http.routers.#{router_name}-tty.middlewares" => "terminal-auth,#{router_name}-tty-strip",
        "traefik.http.middlewares.#{router_name}-tty-strip.stripprefix.prefixes" => "/t/#{route_token}/tty",
        "traefik.http.routers.#{router_name}-tty.service" => "#{router_name}-tty",
        "traefik.http.services.#{router_name}-tty.loadbalancer.server.port" => "7681",

        # File watcher router
        "traefik.http.routers.#{router_name}-fs.rule" => "PathPrefix(`/t/#{route_token}/fs`)",
        "traefik.http.routers.#{router_name}-fs.middlewares" => "terminal-cors,terminal-auth,#{router_name}-fs-strip",
        "traefik.http.middlewares.#{router_name}-fs-strip.stripprefix.prefixes" => "/t/#{route_token}/fs",
        "traefik.http.routers.#{router_name}-fs.service" => "#{router_name}-fs",
        "traefik.http.services.#{router_name}-fs.loadbalancer.server.port" => "4040",

        # IDE router (OpenVSCode Server) — no StripPrefix, server handles path via --server-base-path
        "traefik.http.routers.#{router_name}-ide.rule" => "PathPrefix(`/t/#{route_token}/ide`)",
        "traefik.http.routers.#{router_name}-ide.middlewares" => "terminal-auth",
        "traefik.http.routers.#{router_name}-ide.service" => "#{router_name}-ide",
        "traefik.http.services.#{router_name}-ide.loadbalancer.server.port" => "8443"
      }
    end

    def build_tmpfs_mounts(paths, uid = 1001)
      paths.each_with_object({}) do |path, hash|
        hash[path] = "rw,size=50m,mode=0755,uid=#{uid},gid=#{uid}"
      end
    end
  end
end
