# frozen_string_literal: true

require "docker"

# Manages Docker containers for interactive Claude Code sessions
class ContainerManager
  # Use ttyd image for interactive sessions, Claude session image for agent workflows
  INTERACTIVE_IMAGE = "tsl0922/ttyd:alpine"
  AGENT_IMAGE = "palad-claude-session:latest"
  CONTAINER_PREFIX = "palad"

  class ContainerError < StandardError; end
  class ContainerNotFoundError < ContainerError; end
  class ApiKeyMissingError < ContainerError; end

  class << self
    # Create and start a new session container
    #
    # @param session_id [String] Unique session identifier
    # @param step_name [String] Workflow step name (e.g., "cartographer")
    # @param repo_url [String, nil] Git repository URL to clone
    # @param mounted_artifacts [Array<String>] Paths to artifacts from previous steps
    # @param interactive [Boolean] If true, creates a simple interactive shell container
    # @return [Docker::Container] The created container
    def create_session(session_id:, step_name:, repo_url: nil, mounted_artifacts: [], interactive: true)
      # Only validate API key for non-interactive (agent) sessions
      validate_api_key! unless interactive

      container_name = build_container_name(session_id, step_name)

      # Remove existing container if any
      cleanup_existing_container(container_name)

      # Prepare workspace
      workspace_root = prepare_workspace(session_id, step_name)

      # Build configuration
      volumes = build_volumes(workspace_root, mounted_artifacts)

      # Choose image and configuration based on mode
      if interactive
        image = INTERACTIVE_IMAGE
        env = build_interactive_environment(session_id, step_name)
        # ttyd command: listen on port 7681, writable mode, run bash
        cmd = ["ttyd", "-W", "-p", "7681", "/bin/sh"]
        exposed_ports = { "7681/tcp" => {} }
        port_bindings = { "7681/tcp" => [{ "HostPort" => "0" }] } # Random host port
      else
        image = AGENT_IMAGE
        env = build_environment(session_id, step_name, repo_url)
        cmd = nil
        exposed_ports = nil
        port_bindings = nil
      end

      # Create container
      container_config = {
        "name" => container_name,
        "Image" => image,
        "Tty" => true,
        "OpenStdin" => true,
        "Env" => env,
        "WorkingDir" => "/workspace",
        "HostConfig" => {
          "Binds" => volumes,
          "Memory" => 2 * 1024 * 1024 * 1024, # 2GB
          "CpuPeriod" => 100_000,
          "CpuQuota" => 100_000 # 1 CPU
        }
      }
      container_config["Cmd"] = cmd if cmd
      container_config["ExposedPorts"] = exposed_ports if exposed_ports
      container_config["HostConfig"]["PortBindings"] = port_bindings if port_bindings

      container = Docker::Container.create(container_config)

      container.start

      # Store container ID in Redis for WebSocket lookup
      store_container_id(session_id, step_name, container.id)

      Rails.logger.info("[ContainerManager] Created container #{container_name} (#{container.id[0..11]})")

      container
    end

    # Stop and remove a session container
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    def stop_session(session_id:, step_name:)
      container_id = get_container_id(session_id, step_name)
      return unless container_id

      begin
        container = Docker::Container.get(container_id)
        container.stop(t: 10)
        container.remove(force: true)
        Rails.logger.info("[ContainerManager] Stopped container for session #{session_id}/#{step_name}")
      rescue Docker::Error::NotFoundError
        Rails.logger.warn("[ContainerManager] Container not found: #{container_id}")
      end

      clear_container_id(session_id, step_name)
    end

    # Get container by session and step
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Docker::Container, nil] Container or nil if not found
    def get_container(session_id:, step_name:)
      container_id = get_container_id(session_id, step_name)
      return nil unless container_id

      Docker::Container.get(container_id)
    rescue Docker::Error::NotFoundError
      clear_container_id(session_id, step_name)
      nil
    end

    # Check if container is running
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Boolean] True if container is running
    def container_running?(session_id:, step_name:)
      container = get_container(session_id: session_id, step_name: step_name)
      return false unless container

      container.info["State"]["Running"]
    end

    # Get ttyd WebSocket URL for interactive container
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Hash, nil] Hash with host and port, or nil if not available
    def get_ttyd_url(session_id:, step_name:)
      container = get_container(session_id: session_id, step_name: step_name)
      return nil unless container

      # Refresh container info to get port bindings
      container = Docker::Container.get(container.id)
      port_bindings = container.info.dig("NetworkSettings", "Ports", "7681/tcp")

      return nil unless port_bindings&.any?

      host_port = port_bindings.first["HostPort"]
      {
        host: "localhost",
        port: host_port.to_i,
        ws_url: "ws://localhost:#{host_port}/ws"
      }
    end

    # Attach to container for PTY communication
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Array] [stdin_socket, stdout_socket] for bidirectional communication
    def attach(session_id:, step_name:)
      container = get_container(session_id: session_id, step_name: step_name)
      raise ContainerNotFoundError, "Container not found for #{session_id}/#{step_name}" unless container

      container.attach(
        stream: true,
        stdin: true,
        stdout: true,
        stderr: true,
        tty: true,
        logs: false
      )
    end

    # Get output directory path for a session step
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Pathname] Path to output directory
    def output_path(session_id, step_name)
      workspace_root(session_id).join(step_name, "output")
    end

    # Collect artifacts from completed session
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Array<Hash>] Array of artifact metadata
    def collect_artifacts(session_id:, step_name:)
      output_dir = output_path(session_id, step_name)
      return [] unless output_dir.exist?

      artifacts = []
      output_dir.glob("**/*").each do |file|
        next if file.directory?

        relative_path = file.relative_path_from(output_dir)
        artifacts << {
          path: relative_path.to_s,
          full_path: file.to_s,
          size: file.size,
          created_at: file.ctime
        }
      end

      Rails.logger.info("[ContainerManager] Collected #{artifacts.size} artifacts from #{session_id}/#{step_name}")
      artifacts
    end

    private

    def validate_api_key!
      return if ENV["ANTHROPIC_API_KEY"].present?

      raise ApiKeyMissingError, "ANTHROPIC_API_KEY environment variable is not set"
    end

    def build_container_name(session_id, step_name)
      "#{CONTAINER_PREFIX}-#{session_id}-#{step_name}"
    end

    def cleanup_existing_container(container_name)
      container = Docker::Container.get(container_name)
      container.remove(force: true)
      Rails.logger.info("[ContainerManager] Removed existing container: #{container_name}")
    rescue Docker::Error::NotFoundError
      # Container doesn't exist, nothing to clean up
    end

    def workspace_root(session_id)
      Rails.root.join("tmp", "workspaces", session_id)
    end

    def prepare_workspace(session_id, step_name)
      root = workspace_root(session_id)
      output_dir = root.join(step_name, "output")

      FileUtils.mkdir_p(output_dir)

      root
    end

    def build_volumes(workspace_root, mounted_artifacts)
      step_output = workspace_root.glob("*/output").first || workspace_root.join("default", "output")
      FileUtils.mkdir_p(step_output)

      volumes = [
        "#{step_output}:/workspace/output:rw"
      ]

      # Mount repo if exists
      repo_path = workspace_root.join("repo")
      if repo_path.exist?
        volumes << "#{repo_path}:/workspace/repo:ro"
      end

      # Mount previous step artifacts as context
      mounted_artifacts.each_with_index do |artifact_path, index|
        next unless File.exist?(artifact_path)

        volumes << "#{artifact_path}:/workspace/context/step-#{index + 1}:ro"
      end

      volumes
    end

    def build_environment(session_id, step_name, repo_url)
      env = [
        "SESSION_ID=#{session_id}",
        "STEP_NAME=#{step_name}",
        "ANTHROPIC_API_KEY=#{ENV.fetch('ANTHROPIC_API_KEY')}",
        "MODEL=#{ENV.fetch('CLAUDE_MODEL', 'claude-sonnet-4-20250514')}"
      ]

      env << "REPO_URL=#{repo_url}" if repo_url.present?

      env
    end

    def build_interactive_environment(session_id, step_name)
      [
        "SESSION_ID=#{session_id}",
        "STEP_NAME=#{step_name}",
        "TERM=xterm-256color",
        "PS1=\\[\\033[01;32m\\]\\u@palad\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
      ]
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end

    def redis_key(session_id, step_name)
      "#{CONTAINER_PREFIX}:#{session_id}:#{step_name}:container"
    end

    def store_container_id(session_id, step_name, container_id)
      redis.set(redis_key(session_id, step_name), container_id)
    end

    def get_container_id(session_id, step_name)
      redis.get(redis_key(session_id, step_name))
    end

    def clear_container_id(session_id, step_name)
      redis.del(redis_key(session_id, step_name))
    end
  end
end
