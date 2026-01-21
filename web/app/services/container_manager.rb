# frozen_string_literal: true

require "docker"

# Manages Docker containers for interactive AI agent sessions
class ContainerManager
  CONTAINER_PREFIX = "palad"

  # Agent configurations
  # api_key_required: false means the agent can start without an API key (for interactive setup)
  AGENTS = {
    "claude_code" => {
      image: "palad/claude-code:latest",
      api_key_env: "ANTHROPIC_API_KEY",
      api_key_setting: -> { Settings.anthropic&.api_key },
      api_key_required: true,
      home_dir: "/home/claude",
      display_name: "Claude Code"
    },
    "cursor_cli" => {
      image: "palad/cursor-cli:latest",
      api_key_env: "CURSOR_API_KEY",
      api_key_setting: -> { Settings.cursor&.api_key },
      api_key_required: false, # Can login interactively
      home_dir: "/home/cursor",
      display_name: "Cursor CLI"
    },
    "codex" => {
      image: "palad/codex:latest",
      api_key_env: "OPENAI_API_KEY",
      api_key_setting: -> { Settings.openai&.api_key },
      api_key_required: false, # Can login interactively
      home_dir: "/home/codex",
      display_name: "OpenAI Codex"
    },
    "open_code" => {
      image: "palad/open-code:latest",
      api_key_env: "OPENAI_API_KEY", # Can use either OpenAI or Anthropic
      api_key_setting: -> { Settings.openai&.api_key || Settings.anthropic&.api_key },
      api_key_required: false, # Can work with local models
      home_dir: "/home/opencode",
      display_name: "Open Code"
    }
  }.freeze

  DEFAULT_AGENT = "claude_code"

  class ContainerError < StandardError; end
  class ContainerNotFoundError < ContainerError; end
  class ApiKeyMissingError < ContainerError; end
  class InvalidAgentError < ContainerError; end

  class << self
    # List available agents
    #
    # @return [Array<Hash>] List of available agents with their info
    def available_agents
      AGENTS.map do |type, config|
        {
          type: type,
          display_name: config[:display_name],
          image: config[:image],
          configured: config[:api_key_setting].call.present?
        }
      end
    end

    # Create and start a new session container
    #
    # @param session_id [String] Unique session identifier
    # @param agent_type [String] Type of agent (claude_code, cursor_cli, codex, open_code)
    # @param repo_url [String, nil] Git repository URL to clone
    # @param repo_branch [String, nil] Git branch to checkout
    # @return [Docker::Container] The created container
    def create_session(session_id:, agent_type: DEFAULT_AGENT, repo_url: nil, repo_branch: nil)
      agent_config = get_agent_config(agent_type)
      validate_api_key!(agent_config)

      container_name = build_container_name(session_id, agent_type)

      # Remove existing container if any
      cleanup_existing_container(container_name)

      # Prepare workspace
      workspace_path = prepare_workspace(session_id, agent_type)

      container = Docker::Container.create(
        "name" => container_name,
        "Image" => agent_config[:image],
        "Tty" => true,
        "OpenStdin" => true,
        "Env" => build_environment(session_id, agent_type, agent_config, repo_url, repo_branch),
        "WorkingDir" => "/workspace",
        "ExposedPorts" => {
          "7681/tcp" => {},  # ttyd
          "4040/tcp" => {}   # watcher
        },
        "HostConfig" => {
          "Binds" => build_volume_binds(workspace_path),
          "PortBindings" => {
            "7681/tcp" => [ { "HostPort" => "0" } ],
            "4040/tcp" => [ { "HostPort" => "0" } ]
          },
          "Memory" => 2 * 1024 * 1024 * 1024, # 2GB
          "CpuPeriod" => 100_000,
          "CpuQuota" => 100_000 # 1 CPU
        }
      )

      container.start

      # Store container ID in Redis for lookup
      store_container_id(session_id, agent_type, container.id)

      Rails.logger.info("[ContainerManager] Created #{agent_type} container #{container_name} (#{container.id[0..11]})")

      container
    end

    # Stop and remove a session container
    #
    # @param session_id [String] Session identifier
    # @param agent_type [String] Agent type
    def stop_session(session_id:, agent_type: DEFAULT_AGENT)
      container_id = get_container_id(session_id, agent_type)
      return unless container_id

      begin
        container = Docker::Container.get(container_id)
        container.stop(t: 10)
        container.remove(force: true)
        Rails.logger.info("[ContainerManager] Stopped container for session #{session_id}/#{agent_type}")
      rescue Docker::Error::NotFoundError
        Rails.logger.warn("[ContainerManager] Container not found: #{container_id}")
      end

      clear_container_id(session_id, agent_type)
    end

    # Get container by session and agent type
    #
    # @param session_id [String] Session identifier
    # @param agent_type [String] Agent type
    # @return [Docker::Container, nil] Container or nil if not found
    def get_container(session_id:, agent_type: DEFAULT_AGENT)
      container_id = get_container_id(session_id, agent_type)
      return nil unless container_id

      Docker::Container.get(container_id)
    rescue Docker::Error::NotFoundError
      clear_container_id(session_id, agent_type)
      nil
    end

    # Check if container is running
    #
    # @param session_id [String] Session identifier
    # @param agent_type [String] Agent type
    # @return [Boolean] True if container is running
    def container_running?(session_id:, agent_type: DEFAULT_AGENT)
      container = get_container(session_id: session_id, agent_type: agent_type)
      return false unless container

      container.info["State"]["Running"]
    end

    # Get all service URLs for a session container
    #
    # @param session_id [String] Session identifier
    # @param agent_type [String] Agent type
    # @return [Hash] Hash with ttyd and watcher URLs
    def get_session_urls(session_id:, agent_type: DEFAULT_AGENT)
      container = get_container(session_id: session_id, agent_type: agent_type)
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

    # Get output directory path for a session
    #
    # @param session_id [String] Session identifier
    # @param agent_type [String] Agent type
    # @return [Pathname] Path to output directory
    def output_path(session_id, agent_type = DEFAULT_AGENT)
      workspace_path(session_id, agent_type).join("output")
    end

    private

    def get_agent_config(agent_type)
      config = AGENTS[agent_type]
      raise InvalidAgentError, "Unknown agent type: #{agent_type}" unless config

      config
    end

    def validate_api_key!(agent_config)
      # Skip validation if API key is not required for this agent
      return unless agent_config[:api_key_required]
      return if agent_config[:api_key_setting].call.present?

      raise ApiKeyMissingError, "#{agent_config[:api_key_env]} environment variable is not set"
    end

    def build_container_name(session_id, agent_type)
      "#{CONTAINER_PREFIX}-#{session_id}-#{agent_type}"
    end

    def cleanup_existing_container(container_name)
      container = Docker::Container.get(container_name)
      container.remove(force: true)
      Rails.logger.info("[ContainerManager] Removed existing container: #{container_name}")
    rescue Docker::Error::NotFoundError
      # Container doesn't exist, nothing to clean up
    end

    def workspace_path(session_id, agent_type)
      Rails.root.join("tmp", "workspaces", session_id, agent_type)
    end

    def prepare_workspace(session_id, agent_type)
      path = workspace_path(session_id, agent_type)
      FileUtils.mkdir_p(path.join("output"))
      FileUtils.mkdir_p(path.join("repo"))
      path
    end

    def build_volume_binds(workspace_path)
      [ "#{workspace_path}:/workspace:rw" ]
    end

    def build_environment(session_id, agent_type, agent_config, repo_url, repo_branch)
      env = [
        "SESSION_ID=#{session_id}",
        "AGENT_TYPE=#{agent_type}",
        "TERM=xterm-256color",
        "HOME=#{agent_config[:home_dir]}",
        "TTYD_PORT=7681",
        "WATCHER_PORT=4040"
      ]

      # Add API key
      api_key = agent_config[:api_key_setting].call
      env << "#{agent_config[:api_key_env]}=#{api_key}" if api_key.present?

      # For Open Code, add both keys if available
      if agent_type == "open_code"
        env << "ANTHROPIC_API_KEY=#{Settings.anthropic&.api_key}" if Settings.anthropic&.api_key.present?
        env << "OPENAI_API_KEY=#{Settings.openai&.api_key}" if Settings.openai&.api_key.present?
      end

      env << "REPO_URL=#{repo_url}" if repo_url.present?
      env << "REPO_BRANCH=#{repo_branch}" if repo_branch.present?

      env
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end

    def redis_key(session_id, agent_type)
      "#{CONTAINER_PREFIX}:#{session_id}:#{agent_type}:container"
    end

    def store_container_id(session_id, agent_type, container_id)
      redis.set(redis_key(session_id, agent_type), container_id)
    end

    def get_container_id(session_id, agent_type)
      redis.get(redis_key(session_id, agent_type))
    end

    def clear_container_id(session_id, agent_type)
      redis.del(redis_key(session_id, agent_type))
    end
  end
end
