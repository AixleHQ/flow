# frozen_string_literal: true

module Runners
  # One subclass per runner type (docs/design/agent-runtimes/DESIGN.md §5.1).
  # `Adapter.for(runner)` is the registry. A type without an adapter cannot be
  # created: coder arrives with §15 task 17, kubernetes with phase 6.
  class Adapter
    class UnavailableType < StandardError; end

    # What a type's health check finds (§2.5): one of Runner's health statuses,
    # `pending` for a runner whose first machine has not registered yet, and the
    # reason for people. Runners::HealthCheck applies it.
    Health = Data.define(:status, :reason)

    REGISTRY = { "manual" => "Runners::ManualAdapter" }.freeze

    class << self
      def for(runner) = for_type(runner.runner_type)

      def for_type(type)
        name = REGISTRY[type.to_s]
        raise UnavailableType, "#{type.presence || 'This'} runners are not available yet" if name.nil?

        name.constantize.new
      end

      def available_types = REGISTRY.keys

      def type = raise(NotImplementedError)
      def config_schema = ConfigSchema.for_type(type)
    end

    def type = self.class.type
    def config_schema = self.class.config_schema

    # The behaviour layer: what the type does, which for coder and kubernetes
    # calls their APIs. The config rules are not here: they are data and pure
    # functions in ConfigSchema, which `Runner`'s validation calls.
    def capabilities(_runner) = raise(NotImplementedError)

    # The runner's health from what the platform already knows, with no
    # outbound call for a `manual` runner (§2.5, §5). Returns a Health.
    def check_health(_runner) = raise(NotImplementedError)
  end
end
