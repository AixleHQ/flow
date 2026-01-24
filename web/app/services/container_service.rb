# frozen_string_literal: true

require "docker"
require "net/http"

# Container Service
# Manages Docker container lifecycle for terminal sessions
# Uses docker-api gem for real Docker integration
#
# Architecture:
#   - Rails = Control Plane (session management, auth)
#   - Traefik = Data Plane (WebSocket proxy to containers)
#
# Traefik routes:
#   - /s/{session_id}/tty → container:7681 (ttyd terminal)
#   - /s/{session_id}/fs  → container:4040 (file watcher)

class ContainerService
  class ContainerError < StandardError; end

  # Docker network for Traefik routing
  DOCKER_NETWORK = ENV.fetch("DOCKER_NETWORK", "app_default")

  # Base URL for Traefik (configurable for dev/prod)
  TRAEFIK_WS_BASE = ENV.fetch("TRAEFIK_WS_BASE", "ws://localhost")
  TRAEFIK_HTTP_BASE = ENV.fetch("TRAEFIK_HTTP_BASE", "http://localhost")

  class << self
    # Start authentication container
    # Returns: { container_id:, container_name:, websocket_url:, watcher_url: }
    #
    # @param user_id [Integer] User ID
    # @param agent_type [String] Agent type (claude_code, cursor_cli, etc.)
    # @param websocket_token [String] Token for auth verification
    # @param session_id [Integer] Terminal session ID
    def start_auth_container(user_id, agent_type, websocket_token: nil, session_id: nil)
      validate_agent_type!(agent_type)
      raise ArgumentError, "session_id is required" unless session_id.present?

      image = image_for_agent(agent_type)
      container_name = "terminal-s#{session_id}-#{Time.now.to_i}"

      Rails.logger.info("Starting auth container for #{agent_type}, user: #{user_id}, session: #{session_id}")
      Rails.logger.info("Image: #{image}, Name: #{container_name}")

      # Build environment variables
      env_vars = [
        "USER_ID=#{user_id}",
        "AGENT_TYPE=#{agent_type}",
        "SESSION_TYPE=auth_setup",
        "SESSION_ID=#{session_id}",
        "TTYD_PORT=7681",
        "WATCHER_PORT=4040",
        "TTYD_CMD=#{command_for_agent(agent_type)}"
      ]

      # Token for verifying auth callback requests
      env_vars << "WEBSOCKET_TOKEN=#{websocket_token}" if websocket_token.present?
      # Callback URL for watcher to notify Rails when auth is detected
      env_vars << "AUTH_CALLBACK_URL=http://web:4000/api/v1/internal/auth_callback"

      # Traefik labels for dynamic routing
      traefik_labels = build_traefik_labels(session_id)

      container = Docker::Container.create(
        "name" => container_name,
        "Image" => image,
        "Env" => env_vars,
        "ExposedPorts" => {
          "7681/tcp" => {},  # ttyd
          "4040/tcp" => {}   # watcher
        },
        "HostConfig" => {
          # Use Traefik on shared docker network (no host port bindings)
          "NetworkMode" => DOCKER_NETWORK,
          # Temporary filesystem for home directory (credentials stored here)
          "Tmpfs" => {
            "/home/claude" => "rw,size=100m,mode=0755"
          },
          "AutoRemove" => false
        },
        "Labels" => {
          "palad.session_type" => "auth_setup",
          "palad.agent_type" => agent_type,
          "palad.user_id" => user_id.to_s,
          "palad.session_id" => session_id.to_s,
          "palad.ttyd_port" => "7681"
        }.merge(traefik_labels)
      )

      # Start container
      container.start
      Rails.logger.info("Container started: #{container.id}")

      # Wait for ttyd to be ready (internal health check)
      wait_for_container_health(container.id)

      # URLs - always through Traefik so multiple terminals can coexist
      websocket_url = "#{TRAEFIK_WS_BASE}/s/#{session_id}/tty/ws"
      watcher_url = "#{TRAEFIK_WS_BASE}/s/#{session_id}/fs"

      Rails.logger.info("Container ready. TTY: #{websocket_url} (port: 7681), Watcher: #{watcher_url}")

      {
        container_id: container.id[0..11],
        container_name: container_name,
        websocket_url: websocket_url,
        watcher_url: watcher_url
      }
    rescue Docker::Error::DockerError => e
      Rails.logger.error("Docker error starting container: #{e.message}")
      raise ContainerError, "Failed to start container: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Error starting container: #{e.message}")
      raise ContainerError, "Failed to start container: #{e.message}"
    end

    # Start agent session container (for future Epic 4)
    def start_agent_container(user_id, agent_type, project_id, credentials = nil)
      # Will be implemented in Epic 4
      raise NotImplementedError, "Agent session containers not yet implemented (Epic 4)"
    end

    # Extract files from container
    # Returns: { path => contents }
    def extract_files(container_id, paths)
      Rails.logger.info("Extracting files from #{container_id}: #{paths}")

      container = Docker::Container.get(container_id)
      result = {}

      paths.each do |path|
        begin
          # Create temp file
          temp_file = Tempfile.new(["container-file", ".tar"])
          temp_path = temp_file.path
          temp_file.close

          # Extract file from container (returns TAR archive)
          tar_data = container.copy(path)
          File.binwrite(temp_path, tar_data)

          # Extract from TAR
          content = extract_from_tar(temp_path, File.basename(path))
          result[path] = content if content

          Rails.logger.info("Extracted #{path}: #{content&.bytesize || 0} bytes")
        rescue Docker::Error::NotFoundError
          Rails.logger.warn("File not found in container: #{path}")
          result[path] = nil
        rescue StandardError => e
          Rails.logger.error("Error extracting #{path}: #{e.message}")
          result[path] = nil
        ensure
          File.delete(temp_path) if temp_path && File.exist?(temp_path)
        end
      end

      result
    rescue Docker::Error::NotFoundError
      Rails.logger.error("Container not found: #{container_id}")
      raise ContainerError, "Container not found: #{container_id}"
    rescue StandardError => e
      Rails.logger.error("Error extracting files: #{e.message}")
      raise ContainerError, "Failed to extract files: #{e.message}"
    end

    # Stop and remove container
    def stop_container(container_id)
      Rails.logger.info("Stopping container #{container_id}")

      container = Docker::Container.get(container_id)
      container.stop("t" => 5) # Graceful shutdown with 5s timeout
      container.remove
      Rails.logger.info("Container stopped and removed: #{container_id}")

      true
    rescue Docker::Error::NotFoundError
      Rails.logger.warn("Container not found (already removed?): #{container_id}")
      true # Consider this success - container is gone
    rescue StandardError => e
      Rails.logger.error("Error stopping container: #{e.message}")
      false
    end

    # Health check - verify container is ready
    def health_check(container_id, _port)
      Rails.logger.info("Health check for #{container_id}")

      container = Docker::Container.get(container_id)
      state = container.json["State"]

      if state["Running"]
        Rails.logger.info("Container is running")
        true
      else
        Rails.logger.warn("Container is not running: #{state["Status"]}")
        false
      end
    rescue Docker::Error::NotFoundError
      Rails.logger.error("Container not found: #{container_id}")
      false
    rescue StandardError => e
      Rails.logger.error("Health check error: #{e.message}")
      false
    end

    private

    def validate_agent_type!(agent_type)
      valid_types = %w[claude_code cursor_cli codex gemini_cli]
      raise ArgumentError, "Invalid agent_type: #{agent_type}" unless valid_types.include?(agent_type)
    end

    def image_for_agent(agent_type)
      {
        "claude_code" => "palad/claude-code:latest",
        "cursor_cli" => "palad/cursor-cli:latest",
        "codex" => "palad/codex:latest",
        "gemini_cli" => "palad/gemini-cli:latest"
      }[agent_type]
    end

    def command_for_agent(agent_type)
      {
        "claude_code" => "claude",
        "cursor_cli" => "cursor",
        "codex" => "codex",
        "gemini_cli" => "gemini"
      }[agent_type]
    end

    # Build Traefik labels for dynamic routing
    # Routes:
    #   /s/{session_id}/tty/* → container:7681 (ttyd)
    #   /s/{session_id}/fs/*  → container:4040 (watcher)
    def build_traefik_labels(session_id)
      router_name = "terminal-#{session_id}"
      {
        # Enable Traefik for this container
        "traefik.enable" => "true",

        # TTY router (ttyd terminal)
        "traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/s/#{session_id}/tty`)",
        "traefik.http.routers.#{router_name}-tty.middlewares" => "terminal-auth,#{router_name}-tty-strip",
        "traefik.http.middlewares.#{router_name}-tty-strip.stripprefix.prefixes" => "/s/#{session_id}/tty",
        "traefik.http.routers.#{router_name}-tty.service" => "#{router_name}-tty",
        "traefik.http.services.#{router_name}-tty.loadbalancer.server.port" => "7681",

        # File watcher router
        "traefik.http.routers.#{router_name}-fs.rule" => "PathPrefix(`/s/#{session_id}/fs`)",
        "traefik.http.routers.#{router_name}-fs.middlewares" => "terminal-auth,#{router_name}-fs-strip",
        "traefik.http.middlewares.#{router_name}-fs-strip.stripprefix.prefixes" => "/s/#{session_id}/fs",
        "traefik.http.routers.#{router_name}-fs.service" => "#{router_name}-fs",
        "traefik.http.services.#{router_name}-fs.loadbalancer.server.port" => "4040"
      }
    end

    def wait_for_container_health(container_id, timeout: 30)
      start_time = Time.current

      loop do
        container = Docker::Container.get(container_id)
        state = container.json["State"]
        Rails.logger.info("Container #{container_id[0..11]} state: #{state.inspect}")

        if state["Running"]
          Rails.logger.info("Container #{container_id[0..11]} is running")
          # Give services a moment to start
          sleep 2
          return true
        end

        if state["Status"] == "exited" || state["Status"] == "dead"
          Rails.logger.error("Container exited with code: #{state["ExitCode"]}")
          raise ContainerError, "Container exited with code #{state["ExitCode"]}"
        end

        if Time.current - start_time > timeout
          Rails.logger.error("Container health check timeout after #{timeout}s. State: #{state.inspect}")
          stop_container(container_id) rescue nil
          raise ContainerError, "Container failed to start within #{timeout}s"
        end

        sleep 1
      end
    rescue Docker::Error::NotFoundError
      Rails.logger.error("Container not found: #{container_id}")
      raise ContainerError, "Container not found: #{container_id}"
    end

    # Extract file from TAR archive
    def extract_from_tar(tar_path, filename)
      require "rubygems/package"

      File.open(tar_path, "rb") do |file|
        Gem::Package::TarReader.new(file) do |tar|
          tar.each do |entry|
            if entry.full_name == filename || entry.full_name.end_with?("/#{filename}")
              return entry.read
            end
          end
        end
      end

      nil
    end
  end
end
