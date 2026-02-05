# frozen_string_literal: true

require "docker"

module ContainerStrategies
  # BaseStrategy
  # Abstract base class for container execution strategies
  #
  # Provides default implementations for common lifecycle phases:
  #   - before_create: Build container configuration
  #   - create: Create Docker container
  #   - start: Start container and health check
  #   - cleanup: Stop and remove container
  #
  # Subclasses should implement:
  #   - resolve_image: Return Docker image name
  #   - exec: Main execution logic
  #
  # Subclasses may override:
  #   - build_env_vars, build_labels, build_host_config, build_exposed_ports
  #   - before_exec, before_cleanup (for file injection, artifact collection)
  #   - timeout_for(phase) to customize timeouts
  #
  # @example
  #   class ToolExecutionStrategy < BaseStrategy
  #     def resolve_image
  #       input[:tool].docker_image
  #     end
  #
  #     def exec(context)
  #       # Execute tool command
  #     end
  #   end
  #
  class BaseStrategy
    DOCKER_NETWORK = ENV.fetch("DOCKER_NETWORK", "app_default")
    HEALTH_CHECK_TIMEOUT = 30
    HEALTH_CHECK_INTERVAL = 1

    attr_reader :input

    def initialize(input = {})
      @input = input.is_a?(Hash) ? input.with_indifferent_access : input
    end

    # == Lifecycle Phase: pull_image ==
    # Pull Docker image from registry (fast path if cached)
    #
    # @return [Hash] { status: :cached|:pulled, image:, duration_seconds: }
    def pull_image
      image = resolve_image
      raise ArgumentError, "image is required" if image.blank?

      Rails.logger.info("[#{strategy_name}] Checking image: #{image}")

      if image_exists?(image)
        Rails.logger.info("[#{strategy_name}] Image cached: #{image}")
        return { status: :cached, image: image, duration_seconds: 0 }
      end

      Rails.logger.info("[#{strategy_name}] Pulling image: #{image}")
      start_time = Time.current

      pull_from_registry(image)

      duration = (Time.current - start_time).to_i
      Rails.logger.info("[#{strategy_name}] Image pulled: #{image} (#{duration}s)")

      { status: :pulled, image: image, duration_seconds: duration }
    end

    # == Lifecycle Phase: before_create ==
    # Prepare container configuration
    #
    # Populates context with:
    #   - :image - Docker image name
    #   - :env_vars - Array of "KEY=value" strings
    #   - :labels - Hash of container labels
    #   - :host_config - Docker HostConfig hash
    #   - :exposed_ports - Hash of exposed ports
    #   - :cmd - Optional command to run
    #   - :working_dir - Optional working directory
    #
    # @param context [Hash] Shared context
    def before_create(context)
      context[:image] = resolve_image
      context[:env_vars] = build_env_vars
      context[:labels] = build_labels
      context[:host_config] = build_host_config
      context[:exposed_ports] = build_exposed_ports
      context[:cmd] = build_cmd
      context[:working_dir] = build_working_dir
    end

    # == Lifecycle Phase: create ==
    # Create Docker container
    #
    # @param context [Hash] Shared context (expects :image, :env_vars, etc.)
    def create(context)
      config = {
        "Image" => context[:image],
        "Env" => context[:env_vars] || [],
        "Labels" => context[:labels] || {},
        "HostConfig" => context[:host_config] || {}
      }

      # Optional fields
      config["Cmd"] = context[:cmd] if context[:cmd]
      config["WorkingDir"] = context[:working_dir] if context[:working_dir]
      config["ExposedPorts"] = context[:exposed_ports] if context[:exposed_ports]
      config["name"] = context[:container_name] if context[:container_name]

      context[:container] = Docker::Container.create(config)
    end

    # == Lifecycle Phase: start ==
    # Start container and wait for health
    #
    # @param context [Hash] Shared context (expects :container)
    def start(context)
      container = context[:container]
      container.start

      wait_for_container_health(container)
    end

    # == Lifecycle Phase: cleanup ==
    # Hook called before cleanup (e.g., artifact extraction)
    # Override in subclass to implement custom logic
    #
    # @param context [Hash] Shared context (expects :container, :session)
    def before_cleanup(context)
      # No-op by default
    end

    # Stop and remove container, optionally remove image
    # Can work with container object or container_id
    #
    # @param context [Hash] Shared context (expects :container or :container_id)
    # @return [Hash] { status: :cleaned_up | :not_found | :force_removed | :failed }
    def cleanup(context)
      container = context[:container]
      container_id = context[:container_id]

      # Get container if only ID provided
      if container.nil? && container_id.present?
        container = Docker::Container.get(container_id)
      end

      return { status: :skipped } unless container

      # Stop and remove
      result = cleanup_container(container)

      # Optionally remove image
      cleanup_image(context[:image]) if remove_image_after_cleanup?

      result
    rescue Docker::Error::NotFoundError
      { status: :not_found, container_id: container_id }
    end

    # Whether to remove Docker image after cleanup
    # Override in subclass to enable (e.g., for one-time tool containers)
    # @return [Boolean]
    def remove_image_after_cleanup?
      false
    end

    # == Template Methods (override in subclasses) ==

    # Return Docker image name
    # @return [String] Image name with tag
    def resolve_image
      raise NotImplementedError, "#{self.class.name} must implement #resolve_image"
    end

    # Return array of environment variables
    # @return [Array<String>] Array of "KEY=value" strings
    def build_env_vars
      []
    end

    # Return container labels
    # @return [Hash] Labels hash
    def build_labels
      {}
    end

    # Return Docker HostConfig
    # @return [Hash] HostConfig hash
    def build_host_config
      base_host_config
    end

    # Return HostConfig with resource limits (for tool execution)
    # Note: Subclasses that override build_host_config should NOT call this method
    # from build_host_config to avoid recursion. Use base_host_config instead.
    # @return [Hash] HostConfig with limits
    def build_host_config_with_limits
      limits = container_limits

      base_host_config.merge(
        "Memory" => limits[:memory_bytes],
        "MemorySwap" => limits[:memory_bytes],  # Same as memory (no swap)
        "CpuPeriod" => 100_000,
        "CpuQuota" => limits[:cpu_quota],
        "PidsLimit" => limits[:pids_limit]
      )
    end

    # Base host config without resource limits
    # @return [Hash] Base HostConfig hash
    def base_host_config
      {
        "NetworkMode" => DOCKER_NETWORK,
        "AutoRemove" => false
      }
    end

    # Return exposed ports hash
    # @return [Hash, nil] Exposed ports or nil
    def build_exposed_ports
      nil
    end

    # Return command to run
    # @return [Array<String>, nil] Command or nil
    def build_cmd
      nil
    end

    # Return working directory
    # @return [String, nil] Working directory or nil
    def build_working_dir
      nil
    end

    # Override timeout for specific phase
    # @param phase [Symbol] Phase name
    # @return [Integer, nil] Timeout in seconds or nil for default
    def timeout_for(phase)
      nil
    end

    # Wait for container to be running and healthy
    #
    # @param container [Docker::Container] Container instance
    # @param timeout [Integer] Max wait time in seconds
    def wait_for_container_health(container, timeout: HEALTH_CHECK_TIMEOUT)
      start_time = Time.current

      loop do
        # Refresh container state
        container.refresh!
        state = container.json["State"]

        if state["Running"]
          Rails.logger.info("[#{self.class.name}] Container is running")
          # Wait for services to start (ttyd needs a moment)
          wait_for_services(container)
          return true
        end

        if state["Status"] == "exited" || state["Status"] == "dead"
          exit_code = state["ExitCode"]
          raise "Container exited with code #{exit_code}"
        end

        elapsed = Time.current - start_time
        if elapsed > timeout
          raise "Container failed to start within #{timeout}s"
        end

        sleep HEALTH_CHECK_INTERVAL
      end
    end

    # Wait for services to be ready inside container
    # Override in subclasses for custom health checks
    #
    # @param container [Docker::Container] Container instance
    # @param timeout [Integer] Max wait time in seconds
    def wait_for_services(container, timeout: 10)
      ports_to_check = services_ports
      return if ports_to_check.empty?

      start_time = Time.current

      loop do
        all_ready = ports_to_check.all? do |port|
          port_open?(container, port)
        end

        if all_ready
          Rails.logger.info("[#{self.class.name}] All services ready")
          return true
        end

        elapsed = Time.current - start_time
        if elapsed > timeout
          Rails.logger.warn("[#{self.class.name}] Services timeout after #{timeout}s")
          return false
        end

        sleep 0.5
      end
    end

    # Ports to check for service readiness
    # Override in subclasses
    def services_ports
      []
    end

    # Check if port is open inside container
    def port_open?(container, port)
      # Use netstat/ss to check if port is listening
      result = container.exec([ "sh", "-c", "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -q ':#{port.to_s(16).upcase.rjust(4, '0')} ' && echo 'open'" ])
      result[0].join.include?("open")
    rescue StandardError => e
      Rails.logger.debug("[#{self.class.name}] Port check error: #{e.message}")
      false
    end

    # Get resource limits from settings or defaults
    #
    # @return [Hash] Resource limits
    def container_limits
      @container_limits ||= load_container_limits
    end

    private

    def load_container_limits
      defaults = {
        memory_bytes: 1024 * 1024 * 1024, # 1GB
        cpu_quota: 50_000,                 # 50% of 1 CPU
        pids_limit: 100
      }

      return defaults unless defined?(Settings)
      return defaults unless Settings.respond_to?(:container_execution)

      container_config = Settings.container_execution
      return defaults unless container_config.respond_to?(:limits)

      limits_config = container_config.limits&.tool_execution
      return defaults unless limits_config

      {
        memory_bytes: (limits_config.memory_mb || 512) * 1024 * 1024,
        cpu_quota: (limits_config.cpu_percent || 50) * 1000,
        pids_limit: limits_config.pids_limit || 100
      }
    rescue StandardError => e
      Rails.logger.warn("[BaseStrategy] Failed to load limits: #{e.message}") if defined?(Rails)
      defaults
    end

    public

    # Read file from container using exec cat (faster than copy/tar)
    #
    # @param container [Docker::Container] Container instance
    # @param path [String] File path in container
    # @return [String, nil] File contents or nil
    def read_file_from_container(container, path)
      # exec returns [stdout_array, stderr_array, exit_code]
      result = container.exec([ "cat", path ])
      stdout = result[0]
      exit_code = result[2]

      return nil unless exit_code.zero?

      stdout.join
    rescue Docker::Error::NotFoundError
      nil
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to read #{path}: #{e.message}")
      nil
    end

    private

    # Stop and remove container
    #
    # @param container [Docker::Container, nil] Container instance
    def cleanup_container(container)
      return { status: :skipped } unless container

      container_id = container.id[0..11]

      # Stop container
      begin
        container.stop("t" => 5)
      rescue Docker::Error::NotFoundError
        return { status: :not_found, container_id: container_id }
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Stop failed: #{e.message}, force removing")
        return force_remove_container(container, container_id)
      end

      # Remove container
      begin
        container.remove
        Rails.logger.info("[#{strategy_name}] Cleaned up: #{container_id}")
        { status: :cleaned_up, container_id: container_id }
      rescue Docker::Error::NotFoundError
        { status: :not_found, container_id: container_id }
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Remove failed: #{e.message}, force removing")
        force_remove_container(container, container_id)
      end
    end

    def force_remove_container(container, container_id)
      container.remove(force: true)
      Rails.logger.info("[#{strategy_name}] Force removed: #{container_id}")
      { status: :force_removed, container_id: container_id }
    rescue Docker::Error::NotFoundError
      { status: :not_found, container_id: container_id }
    rescue StandardError => e
      Rails.logger.error("[#{strategy_name}] Force remove failed: #{e.message}")
      { status: :failed, container_id: container_id, error: e.message }
    end

    # Remove Docker image
    #
    # @param image [String, nil] Image name
    def cleanup_image(image)
      return unless image

      begin
        docker_image = Docker::Image.get(image)
        docker_image.remove(force: true)
        Rails.logger.info("[#{self.class.name}] Removed image: #{image}")
      rescue Docker::Error::NotFoundError
        # Already gone
      rescue Docker::Error::ConflictError => e
        # Image in use by another container
        Rails.logger.warn("[#{self.class.name}] Cannot remove image #{image}: #{e.message}")
      rescue StandardError => e
        Rails.logger.warn("[#{self.class.name}] Remove image failed: #{e.message}")
      end
    end

    # Check if image exists locally
    def image_exists?(image)
      Docker::Image.get(image)
      true
    rescue Docker::Error::NotFoundError
      false
    end

    # Pull image from registry
    def pull_from_registry(image)
      image_name, tag = parse_image_reference(image)

      Docker::Image.create(
        "fromImage" => image_name,
        "tag" => tag
      ) do |chunk|
        log_pull_progress(chunk)
      end
    end

    # Parse image reference into name and tag
    def parse_image_reference(image)
      if image.include?(":")
        parts = image.rpartition(":")
        [ parts[0], parts[2] ]
      else
        [ image, "latest" ]
      end
    end

    # Log pull progress from Docker API
    def log_pull_progress(chunk)
      return unless chunk.is_a?(String)

      data = JSON.parse(chunk) rescue nil
      return unless data

      if data["status"] && data["progress"]
        Rails.logger.debug("[#{strategy_name}] #{data['status']}: #{data['progress']}")
      end
    end

    # Strategy name for logging
    def strategy_name
      self.class.name.demodulize
    end
  end
end
