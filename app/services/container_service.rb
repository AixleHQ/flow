# frozen_string_literal: true

# ContainerService
# Phase runner for container lifecycle.
#
# Each phase delegates to strategy hooks: before_X, X, after_X.
# Strategy methods receive keyword args and return hashes.
# State accumulates between hooks, each method declares its contract via signature.
#
# No timeout logic — Temporal manages activity timeouts.
# No signal logic — workflow manages signals.
#
# @example
#   service = ContainerService.new(strategy: strategy, state: { session_id: 1 })
#   result = service.run_phase(:create_container)
#   # => { image: "palad/...", container_id: "abc123", session_id: 1 }
#
class ContainerService
  class ExecutionError < StandardError; end
  class PhaseError < ExecutionError
    attr_reader :phase, :original_error

    def initialize(phase, original_error)
      @phase = phase
      @original_error = original_error
      super("Phase #{phase} failed: #{original_error.message}")
    end
  end

  PHASES = %i[pull_image create_container start_container exec cleanup].freeze

  def initialize(strategy:, state: {})
    @strategy = strategy
    @state = {}.merge(state || {}).deep_symbolize_keys
  end

  # Run a single lifecycle phase with before/after hooks.
  # Returns accumulated state (serializable for passing between activities).
  def run_phase(phase)
    phase = phase.to_sym

    Rails.logger.info("[ContainerService] Phase #{phase} starting")
    start_time = Time.current

    @state.merge!(invoke(:"before_#{phase}"))
    @state.merge!(invoke(phase))
    @state.merge!(invoke(:"after_#{phase}"))

    duration = ((Time.current - start_time) * 1000).to_i
    Rails.logger.info("[ContainerService] Phase #{phase} completed in #{duration}ms")

    @state
  rescue StandardError => e
    Rails.logger.error("[ContainerService] Phase #{phase} failed: #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    raise PhaseError.new(phase, e)
  end

  private

  def invoke(hook)
    return {} unless @strategy.respond_to?(hook)

    result = @strategy.public_send(hook, **@state)
    result.is_a?(Hash) ? result.deep_symbolize_keys : {}
  end
end
