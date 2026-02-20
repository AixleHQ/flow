# frozen_string_literal: true

require "timeout"

# ContainerService
# Unified orchestrator for container lifecycle execution using Strategy Pattern
#
# Executes 6 lifecycle phases with per-phase timeout protection:
#   1. before_create  - Validate input, resolve config
#   2. create         - Container create
#   3. before_start   - Configure labels, network, volumes
#   4. start          - Start container + health check
#   5. before_exec    - Inject files/credentials
#   6. exec           - Main execution (command/wait/signal)
#
# Cleanup is done separately via strategy.cleanup() in CleanupContainerActivity
#
# Usage:
#   strategy = ContainerStrategies::ToolExecutionStrategy.new(tool: tool, parameters: params)
#   result = ContainerService.execute(strategy: strategy, input: { ... })
#
class ContainerService
  class ExecutionError < StandardError; end
  class ExecutionTimeout < ExecutionError; end
  class ImageNotFoundError < ExecutionError; end
  class ImagePullError < ExecutionError; end
  class PhaseError < ExecutionError
    attr_reader :phase, :original_error

    def initialize(phase, original_error)
      @phase = phase
      @original_error = original_error
      super("Phase #{phase} failed: #{original_error.message}")
    end
  end

  # Execution phases (cleanup is separate via strategy.cleanup)
  LIFECYCLE_PHASES = %i[
    before_create
    create
    before_start
    start
    before_exec
    exec
  ].freeze

  # Default timeouts in seconds (can be overridden in settings.yml)
  DEFAULT_TIMEOUTS = {
    before_create: 30,
    create: 60,
    before_start: 30,
    start: 60,
    before_exec: 120,
    exec: 300
  }.freeze

  class << self
    # Main entry point for container execution
    # Runs 6 phases: before_create, create, before_start, start, before_exec, exec
    # Cleanup should be called separately via strategy.cleanup()
    #
    # @param strategy [ContainerStrategies::BaseStrategy] Strategy instance (legacy)
    # @param input [Hash] Input parameters (legacy)
    # @param session [TerminalSession] Session to execute (preferred)
    # @return [Hash] Result from strategy execution
    def execute(strategy: nil, input: {}, session: nil)
      if session
        new(session.strategy, session.strategy.input).run
      else
        new(strategy, input).run
      end
    end

    # Cleanup after session execution: before_cleanup (artifacts) + cleanup (stop/remove)
    #
    # @param session [TerminalSession] Session to clean up
    # @return [Hash] Cleanup result
    def cleanup(session:)
      strategy = session.strategy
      container_id = session.container_id

      context = {
        container: container_id.present? ? ContainerRuntime.build.resolve_container(container_id) : nil,
        container_id: container_id,
        session: session,
        result: {}
      }

      strategy.before_cleanup(context) if context[:container]
      cleanup_result = strategy.cleanup(context) || {}

      { **context[:result], status: cleanup_result[:status] || :skipped }
    rescue StandardError => e
      Rails.logger.error("[ContainerService] Cleanup failed for session #{session.id}: #{e.message}")
      { status: :error, error: e.message }
    end
  end

  def initialize(strategy, input)
    @strategy = strategy
    @input = input
    @context = { input: input }
    @completed_phases = []
  end

  # Execute all lifecycle phases in order
  #
  # @return [Hash] Result from context[:result] or empty hash
  def run
    Rails.logger.info("[ContainerService] Starting: #{@strategy.class.name}")

    LIFECYCLE_PHASES.each do |phase|
      execute_phase(phase)
      @completed_phases << phase
    end

    Rails.logger.info("[ContainerService] Completed successfully")
    @context[:result] || {}
  rescue ExecutionTimeout, PhaseError => e
    Rails.logger.error("[ContainerService] Failed: #{e.message}")
    emergency_cleanup
    raise
  rescue StandardError => e
    Rails.logger.error("[ContainerService] Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    emergency_cleanup
    raise PhaseError.new(@current_phase || :unknown, e)
  end

  private

  # Execute a single lifecycle phase with timeout protection
  #
  # @param phase [Symbol] Phase name
  def execute_phase(phase)
    return unless @strategy.respond_to?(phase)

    @current_phase = phase
    timeout = phase_timeout(phase)

    Rails.logger.info("[ContainerService] Phase #{phase} starting (timeout: #{timeout}s)")
    start_time = Time.current

    Timeout.timeout(timeout) do
      @strategy.public_send(phase, @context)
    end

    duration = ((Time.current - start_time) * 1000).to_i
    Rails.logger.info("[ContainerService] Phase #{phase} completed in #{duration}ms")
  rescue Timeout::Error
    handle_timeout(phase, timeout)
  rescue StandardError => e
    handle_error(phase, e)
  end

  # Get timeout for a phase
  # Priority: strategy override > settings > defaults
  #
  # @param phase [Symbol] Phase name
  # @return [Integer] Timeout in seconds
  def phase_timeout(phase)
    # Strategy can override timeouts
    if @strategy.respond_to?(:timeout_for)
      custom_timeout = @strategy.timeout_for(phase)
      return custom_timeout if custom_timeout
    end

    # Try settings.yml
    settings_timeout = settings_timeout_for(phase)
    return settings_timeout if settings_timeout

    # Fall back to defaults
    DEFAULT_TIMEOUTS[phase] || 30
  end

  # Get timeout from Settings (config/settings.yml)
  #
  # @param phase [Symbol] Phase name
  # @return [Integer, nil] Timeout in seconds or nil
  def settings_timeout_for(phase)
    return nil unless defined?(Settings) && Settings.respond_to?(:container_execution)
    return nil unless Settings.container_execution&.respond_to?(:timeouts)

    Settings.container_execution.timeouts[phase.to_s]
  rescue StandardError
    nil
  end

  # Handle timeout error for a phase
  #
  # @param phase [Symbol] Phase name
  # @param timeout [Integer] Timeout that was exceeded
  def handle_timeout(phase, timeout)
    Rails.logger.error("[ContainerService] Phase #{phase} TIMED OUT after #{timeout}s")
    emergency_cleanup
    raise ExecutionTimeout, "Phase #{phase} exceeded timeout of #{timeout}s"
  end

  # Handle general error for a phase
  #
  # @param phase [Symbol] Phase name
  # @param error [StandardError] The error that occurred
  def handle_error(phase, error)
    Rails.logger.error("[ContainerService] Phase #{phase} FAILED: #{error.message}")
    Rails.logger.error(error.backtrace&.first(5)&.join("\n"))

    # Wrap and re-raise
    raise PhaseError.new(phase, error)
  end

  # Emergency cleanup - stop and remove container forcefully
  # Called when execution fails to ensure no orphaned containers
  def emergency_cleanup
    container = @context[:container]
    container_id = @context[:container_id]

    return if container.nil? && container_id.nil?

    Rails.logger.warn("[ContainerService] Performing emergency cleanup")

    begin
      target = container || container_id

      begin
        runtime.stop_container(target, 5)
      rescue StandardError => e
        Rails.logger.warn("[ContainerService] Stop failed: #{e.message}")
      end

      begin
        runtime.remove_container(target, force: true)
        Rails.logger.info("[ContainerService] Container removed")
      rescue StandardError => e
        Rails.logger.warn("[ContainerService] Remove failed: #{e.message}")
      end
    rescue StandardError => e
      Rails.logger.error("[ContainerService] Emergency cleanup failed: #{e.message}")
    end
  end

  def runtime
    @runtime ||= ContainerRuntime.build
  end
end
