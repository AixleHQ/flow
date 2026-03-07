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
    VALID_AGENT_TYPES = %w[claude_code cursor_cli codex gemini_cli].freeze

    DEFAULT_AGENT_IMAGES = {
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
    # Waits for Traefik route, marks session ready, returns URLs for frontend.

    TRAEFIK_ROUTE_TIMEOUT = 30
    TRAEFIK_ROUTE_INTERVAL = 1

    def exec(container_id:, **)
      container_ref = resolve_container(container_id)
      cid = runtime.container_identifier(container_ref)
      raise "Container not ready for exec" if cid.blank?

      route_token = input[:route_token]
      wait_for_traefik_route(route_token)
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
        "AUTH_REQUIRED_KEYS" => agent_service.adapter.auth_required_keys.join(",")
      }

      env_vars.merge!(agent_service.adapter.default_env_vars(session))
      env_vars.merge!(agent_service.adapter.env_vars_from_metadata(session.metadata)) if session.metadata.present?
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
        "Tmpfs" => build_tmpfs_mounts(agent_service.adapter.tmpfs_paths, agent_service.adapter.tmpfs_uid)
      )
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

    def mcp_server_url
      Settings.mcp.server_url
    end

    def mark_session_ready(container_id)
      session = TerminalSession.find(input[:session_id])
      session.update!(container_id: container_id)
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

    def wait_for_traefik_route(route_token)
      traefik_internal = Settings.traefik.internal_url
      url = URI("#{traefik_internal}/t/#{route_token}/tty/")
      deadline = Time.current + TRAEFIK_ROUTE_TIMEOUT

      loop do
        begin
          http = Net::HTTP.new(url.host, url.port)
          http.open_timeout = 2
          http.read_timeout = 2
          response = http.get(url.request_uri)
          unless response.is_a?(Net::HTTPNotFound)
            Rails.logger.info("[#{strategy_name}] Traefik route ready for #{route_token}")
            return
          end
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          Rails.logger.debug("[#{strategy_name}] Traefik not yet ready: #{e.class}")
        end

        if Time.current > deadline
          Rails.logger.warn("[#{strategy_name}] Traefik route timeout for #{route_token}, proceeding anyway")
          return
        end

        sleep TRAEFIK_ROUTE_INTERVAL
      end
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

    def persist_vscode_token(session, token)
      meta = session.metadata || {}
      meta["vscode_token"] = token
      session.update_column(:metadata, meta)
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

    def build_tmpfs_mounts(paths, uid = 1001)
      paths.each_with_object({}) do |path, hash|
        hash[path] = "rw,size=50m,mode=0755,uid=#{uid},gid=#{uid}"
      end
    end
  end
end
