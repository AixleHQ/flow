l# frozen_string_literal: true

require "docker"
require "timeout"

# ContainerExecutionService
# Unified orchestrator for container lifecycle execution using Strategy Pattern
#
# Executes 8 lifecycle phases with per-phase timeout protection:
#   1. before_create  - Validate input, resolve config
#   2. create         - Docker container create
#   3. before_start   - Configure labels, network, volumes
#   4. start          - Start container + health check
#   5. before_exec    - Inject files/credentials
#   6. exec           - Main execution (command/wait/signal)
#   7. before_cleanup - Collect artifacts
#   8. cleanup        - Stop and remove container
#
# Usage:
#   strategy = ContainerStrategies::ToolExecutionStrategy.new(tool: tool, parameters: params)
#   result = ContainerExecutionService.execute(strategy: strategy, input: { ... })
#
class ContainerExecutionService
  class ExecutionError < StandardError; end
  class ExecutionTimeout < ExecutionError; end
  class PhaseError < ExecutionError
    attr_reader :phase, :original_error

    def initialize(phase, original_error)
      @phase = phase
      @original_error = original_error
      super("Phase #{phase} failed: #{original_error.message}")
    end
  end

  LIFECYCLE_PHASES = %i[
    before_create
    create
    before_start
    start
    before_exec
    exec
    before_cleanup
    cleanup
  ].freeze

  # Default timeouts in seconds (can be overridden in settings.yml)
  DEFAULT_TIMEOUTS = {
    before_create: 30,
    create: 60,
    before_start: 30,
    start: 60,
    before_exec: 120,
    exec: 300,
    before_cleanup: 120,
    cleanup: 30
  }.freeze

  class << self
    # Main entry point for container execution
    #
    # @param strategy [ContainerStrategies::BaseStrategy] Strategy instance
    # @param input [Hash] Input parameters (passed to context)
    # @return [Hash] Result from strategy execution
    def execute(strategy:, input: {})
      new(strategy, input).run
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
    Rails.logger.info("[ContainerExecution] Starting execution with strategy: #{@strategy.class.name}")

    LIFECYCLE_PHASES.each do |phase|
      execute_phase(phase)
      @completed_phases << phase
    end

    Rails.logger.info("[ContainerExecution] Execution completed successfully")
    @context[:result] || {}
  rescue ExecutionTimeout, PhaseError => e
    Rails.logger.error("[ContainerExecution] Execution failed: #{e.message}")
    emergency_cleanup unless @completed_phases.include?(:cleanup)
    raise
  rescue StandardError => e
    Rails.logger.error("[ContainerExecution] Unexpected error: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    emergency_cleanup unless @completed_phases.include?(:cleanup)
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

    Rails.logger.info("[ContainerExecution] Phase #{phase} starting (timeout: #{timeout}s)")
    start_time = Time.current

    Timeout.timeout(timeout) do
      @strategy.public_send(phase, @context)
    end

    duration = ((Time.current - start_time) * 1000).to_i
    Rails.logger.info("[ContainerExecution] Phase #{phase} completed in #{duration}ms")
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
    Rails.logger.error("[ContainerExecution] Phase #{phase} TIMED OUT after #{timeout}s")

    # Try emergency cleanup for non-cleanup phases
    emergency_cleanup if phase != :cleanup

    raise ExecutionTimeout, "Phase #{phase} exceeded timeout of #{timeout}s"
  end

  # Handle general error for a phase
  #
  # @param phase [Symbol] Phase name
  # @param error [StandardError] The error that occurred
  def handle_error(phase, error)
    Rails.logger.error("[ContainerExecution] Phase #{phase} FAILED: #{error.message}")
    Rails.logger.error(error.backtrace&.first(5)&.join("\n"))

    # Wrap and re-raise
    raise PhaseError.new(phase, error)
  end

  # Emergency cleanup - kill and remove container forcefully
  # Called when execution fails to ensure no orphaned containers
  def emergency_cleanup
    return unless @context[:container]

    Rails.logger.warn("[ContainerExecution] Performing emergency cleanup")

    begin
      container = @context[:container]

      # Try to kill first (faster than stop)
      begin
        container.kill
        Rails.logger.info("[ContainerExecution] Container killed")
      rescue Docker::Error::NotFoundError
        # Already gone
      rescue StandardError => e
        Rails.logger.warn("[ContainerExecution] Kill failed: #{e.message}")
      end

      # Force remove
      begin
        container.remove(force: true)
        Rails.logger.info("[ContainerExecution] Container removed")
      rescue Docker::Error::NotFoundError
        # Already gone
      rescue StandardError => e
        Rails.logger.warn("[ContainerExecution] Force remove failed: #{e.message}")
      end
    rescue StandardError => e
      Rails.logger.error("[ContainerExecution] Emergency cleanup failed: #{e.message}")
    end
  end
end
