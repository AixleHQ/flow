# frozen_string_literal: true

require "docker"

# Manages Docker containers for interactive Claude Code sessions
class ContainerManager
  IMAGE = "claude-code:latest"
  CONTAINER_PREFIX = "palad"

  class ContainerError < StandardError; end
  class ContainerNotFoundError < ContainerError; end
  class ApiKeyMissingError < ContainerError; end

  class << self
    # Create and start a new session container
    #
    # @param session_id [String] Unique session identifier
    # @param step_name [String] Workflow step name (e.g., "dev")
    # @param repo_url [String, nil] Git repository URL to clone
    # @param repo_branch [String, nil] Git branch to checkout
    # @return [Docker::Container] The created container
    def create_session(session_id:, step_name:, repo_url: nil, repo_branch: nil)
      validate_api_key!

      container_name = build_container_name(session_id, step_name)

      # Remove existing container if any
      cleanup_existing_container(container_name)

      # Prepare workspace
      workspace_path = prepare_workspace(session_id, step_name)

      container = Docker::Container.create(
        "name" => container_name,
        "Image" => IMAGE,
        "Tty" => true,
        "OpenStdin" => true,
        "Env" => build_environment(session_id, step_name, repo_url, repo_branch),
        "WorkingDir" => "/workspace",
        "ExposedPorts" => {
          "7681/tcp" => {},  # ttyd
          "4040/tcp" => {}   # watcher
        },
        "HostConfig" => {
          "Binds" => build_volume_binds(workspace_path),
          "PortBindings" => {
            "7681/tcp" => [{ "HostPort" => "0" }],
            "4040/tcp" => [{ "HostPort" => "0" }]
          },
          "Memory" => 2 * 1024 * 1024 * 1024, # 2GB
          "CpuPeriod" => 100_000,
          "CpuQuota" => 100_000 # 1 CPU
        }
      )

      container.start

      # Store container ID in Redis for lookup
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

    # Get all service URLs for a session container
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Hash] Hash with ttyd and watcher URLs
    def get_session_urls(session_id:, step_name:)
      container = get_container(session_id: session_id, step_name: step_name)
      return nil unless container

      # Refresh container info to get port bindings
      container = Docker::Container.get(container.id)
      ports = container.info.dig("NetworkSettings", "Ports")

      ttyd_port = ports.dig("7681/tcp", 0, "HostPort")
      watcher_port = ports.dig("4040/tcp", 0, "HostPort")

      {
        ttyd: ttyd_port ? {
          port: ttyd_port.to_i,
          ws_url: "ws://localhost:#{ttyd_port}/ws"
        } : nil,
        watcher: watcher_port ? {
          port: watcher_port.to_i,
          ws_url: "ws://localhost:#{watcher_port}",
          http_url: "http://localhost:#{watcher_port}"
        } : nil
      }
    end

    # Get output directory path for a session step
    #
    # @param session_id [String] Session identifier
    # @param step_name [String] Step name
    # @return [Pathname] Path to output directory
    def output_path(session_id, step_name)
      workspace_path(session_id, step_name).join("output")
    end

    private

    def validate_api_key!
      return if Settings.anthropic.api_key.present?

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

    def workspace_path(session_id, step_name)
      Rails.root.join("tmp", "workspaces", session_id, step_name)
    end

    def prepare_workspace(session_id, step_name)
      path = workspace_path(session_id, step_name)
      FileUtils.mkdir_p(path.join("output"))
      FileUtils.mkdir_p(path.join("repo"))
      path
    end

    def build_volume_binds(workspace_path)
      # Claude Code config is baked into the image via managed-settings.json
      # No need to mount external config files
      ["#{workspace_path}:/workspace:rw"]
    end

    def build_environment(session_id, step_name, repo_url, repo_branch)
      env = [
        "SESSION_ID=#{session_id}",
        "STEP_NAME=#{step_name}",
        "TERM=xterm-256color",
        "HOME=/home/claude",
        "CLAUDE_HOME=/home/claude",
        "ANTHROPIC_API_KEY=#{Settings.anthropic.api_key}",
        "TTYD_PORT=7681",
        "WATCHER_PORT=4040"
      ]

      env << "REPO_URL=#{repo_url}" if repo_url.present?
      env << "REPO_BRANCH=#{repo_branch}" if repo_branch.present?

      env
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
