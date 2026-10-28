# frozen_string_literal: true

module Runners
  # One subclass per runner type (docs/design/agent-runtimes/DESIGN.md §5.1).
  # `Adapter.for(runner)` is the registry. A type without an adapter cannot be
  # created: coder arrives with §15 task 17, kubernetes with phase 6.
  class Adapter
    class UnavailableType < StandardError; end

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

    def capabilities(_runner) = raise(NotImplementedError)

    # Errors for the rules one key's schema cannot express. Called once
    # `config` has passed ConfigSchema, so values have their declared types.
    def validate_config(_runner) = []
  end
end
