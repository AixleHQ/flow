# frozen_string_literal: true

module ContainerStrategies
  # BaseStrategy
  # Abstract base class for container execution strategies
  #
  # Provides default implementations for common lifecycle phases:
  #   - before_create: Build container configuration
  #   - create: Create container
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

      runtime.pull_image(image)
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
    # Create container
    #
    # @param context [Hash] Shared context (expects :image, :env_vars, etc.)
    def create(context)
      spec = {
        image: context[:image],
        env_vars: context[:env_vars] || [],
        labels: context[:labels] || {},
        host_config: context[:host_config] || {},
        cmd: context[:cmd],
        working_dir: context[:working_dir],
        exposed_ports: context[:exposed_ports],
        container_name: context[:container_name]
      }

      context[:container] = runtime.create_container(spec)
      context[:container_id] ||= runtime_container_id(context[:container])
    end

    # == Lifecycle Phase: start ==
    # Start container and wait for readiness
    #
    # @param context [Hash] Shared context (expects :container)
    def start(context)
      target = context[:container] || context[:container_id]
      context[:container] = runtime.start_container(target)
      context[:container_id] ||= runtime_container_id(context[:container] || target)

      runtime.wait_for_ready(context[:container] || context[:container_id], services_ports)
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
      container = context[:container] || context[:container_id]
      return { status: :skipped } unless container

      container_id = runtime_container_id(container)

      begin
        runtime.stop_container(container, 5)
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Stop failed: #{e.message}")
      end

      begin
        runtime.remove_container(container)
        runtime.remove_image(context[:image]) if remove_image_after_cleanup?
        { status: :cleaned_up, container_id: container_id }
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Remove failed: #{e.message}")
        { status: :failed, container_id: container_id, error: e.message }
      end
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

    # Ports to check for service readiness
    # Override in subclasses
    def services_ports
      []
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
    # @param container [Object] Runtime container handle
    # @param path [String] File path in container
    # @return [String, nil] File contents or nil
    def read_file_from_container(container, path)
      # exec returns [stdout_array, stderr_array, exit_code]
      result = runtime.exec(container, [ "cat", path ])
      stdout = result[0]
      exit_code = result[2]

      return nil unless exit_code.zero?

      stdout.join
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to read #{path}: #{e.message}")
      nil
    end

    private

    def runtime
      @runtime ||= ContainerRuntime.build
    end

    def runtime_container_id(container)
      return container.id if container.respond_to?(:id)

      container.to_s
    end

    # Strategy name for logging
    def strategy_name
      self.class.name.demodulize
    end
  end
end
