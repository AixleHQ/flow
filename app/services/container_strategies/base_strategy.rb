# frozen_string_literal: true

module ContainerStrategies
  # BaseStrategy
  # Abstract base class for container execution strategies.
  #
  # Phase contract: each method receives keyword args, returns a Hash of what it produced.
  # `**_` swallows state it doesn't need. ContainerService merges results between hooks.
  #
  # Phase flow:
  #   pull_image(**_) → { image: }
  #   before_create_container(**_) → { container_name:, env_vars:, labels:, host_config:, ... }
  #   create_container(image:, env_vars:, labels:, host_config:, **_) → { container_id: }
  #   start_container(container_id:, **_) → {}
  #   exec(container_id:, **_) → { result: { ... } }
  #   before_cleanup(container_id:, **_) → { ... }
  #   cleanup(container_id:, **_) → { status: }
  #   after_cleanup(session_id: nil, error: nil, **_) → {}
  #   on_failure(error: nil, **_) → {}  (called by workflow when execution fails)
  #
  class BaseStrategy
    def self.docker_network
      Settings.docker.network
    end

    attr_reader :input

    def initialize(input = {})
      @input = input.is_a?(Hash) ? input.with_indifferent_access : input
    end

    # == Phase config (for workflow orchestration) ==

    def phase_config(phase)
      { timeout: 300 }
    end

    def build_manifest
      ContainerService::PHASES.each_with_object({}) do |phase, manifest|
        manifest[phase] = phase_config(phase)
      end
    end

    # == pull_image ==

    def pull_image(**)
      image = resolve_image
      raise ArgumentError, "image is required" if image.blank?

      runtime.pull_image(image)
      { image: image }
    end

    # == create_container ==

    def create_container(image:, env_vars: [], labels: {}, host_config: {},
                         cmd: nil, working_dir: nil, exposed_ports: nil, container_name: nil, **)
      spec = {
        image: image,
        env_vars: env_vars,
        labels: labels,
        host_config: host_config,
        cmd: cmd,
        working_dir: working_dir,
        exposed_ports: exposed_ports,
        container_name: container_name,
        namespace_context: build_namespace_context
      }

      container = runtime.create_container(spec)
      { container_id: runtime_container_id(container) }
    end

    # == start_container ==

    def start_container(container_id:, **)
      container = resolve_container(container_id)
      runtime.start_container(container)
      runtime.wait_for_ready(container, services_ports)
      {}
    end

    # == cleanup ==

    def before_cleanup(**)
      {}
    end

    def cleanup(container_id: nil, image: nil, **)
      return { status: :skipped } if container_id.blank?

      container = resolve_container(container_id)

      begin
        runtime.stop_container(container, 5)
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Stop failed: #{e.message}")
      end

      begin
        runtime.remove_container(container)
        runtime.remove_image(image) if image && remove_image_after_cleanup?
        { status: :cleaned_up }
      rescue StandardError => e
        Rails.logger.warn("[#{strategy_name}] Remove failed: #{e.message}")
        { status: :failed, cleanup_error: e.message }
      end
    end

    def after_cleanup(session_id: nil, error: nil, **)
      return {} if session_id.blank?

      session = TerminalSession.find(session_id)
      session.reload

      if error
        session.update(error_message: error)
        session.fail! if session.may_fail?
      else
        session.finish! if session.may_finish?
      end
      {}
    rescue StandardError => e
      Rails.logger.error("[#{strategy_name}] Failed to finalize session: #{e.message}")
      {}
    end

    # Called when workflow fails (after cleanup). Override in subclass to handle failure.
    def on_failure(error: nil, **)
      {}
    end

    def remove_image_after_cleanup?
      false
    end

    # == Template methods ==

    def resolve_image
      raise NotImplementedError, "#{self.class.name} must implement #resolve_image"
    end

    def build_env_vars = []
    def build_labels = {}
    def build_host_config = base_host_config
    def build_exposed_ports = nil
    def build_cmd = nil
    def build_working_dir = nil
    def services_ports = []

    def build_host_config_with_limits
      limits = container_limits
      base_host_config.merge(
        "Memory" => limits[:memory_bytes],
        "MemorySwap" => limits[:memory_bytes],
        "CpuPeriod" => 100_000,
        "CpuQuota" => limits[:cpu_quota],
        "PidsLimit" => limits[:pids_limit]
      )
    end

    def base_host_config
      { "NetworkMode" => self.class.docker_network, "AutoRemove" => false }
    end

    def container_limits
      @container_limits ||= load_container_limits
    end

    def read_file_from_container(container, path)
      result = runtime.exec(container, [ "cat", path ], binary: true)
      return nil unless result[2].zero?

      result[0].map(&:b).join
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] Failed to read #{path}: #{e.message}")
      nil
    end

    protected

    def resolve_container(container_id)
      ContainerRuntime.build.resolve_container(container_id)
    end

    def runtime
      @runtime ||= ContainerRuntime.build
    end

    def runtime_container_id(container)
      runtime.container_identifier(container)
    end

    def strategy_name
      self.class.name.demodulize
    end

    private

    def build_namespace_context
      context = {}
      context[:user_id] = input[:user_id] if input[:user_id].present?

      session = current_terminal_session
      context[:session_id] = session.id if session
      context[:project_id] = session.project_id if session&.project_id.present?

      context.presence
    end

    def current_terminal_session
      return @current_terminal_session if defined?(@current_terminal_session)
      return @current_terminal_session = nil if input[:session_id].blank?

      @current_terminal_session = TerminalSession.find_by(id: input[:session_id])
    end

    def load_container_limits
      defaults = { memory_bytes: 1024 * 1024 * 1024, cpu_quota: 50_000, pids_limit: 100 }

      return defaults unless defined?(Settings) && Settings.respond_to?(:container_execution)

      limits_config = Settings.container_execution&.limits&.tool_execution
      return defaults unless limits_config

      {
        memory_bytes: (limits_config.memory_mb || 512) * 1024 * 1024,
        cpu_quota: (limits_config.cpu_percent || 50) * 1000,
        pids_limit: limits_config.pids_limit || 100
      }
    rescue StandardError
      defaults
    end
  end
end
