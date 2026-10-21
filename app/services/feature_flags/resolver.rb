# frozen_string_literal: true

module FeatureFlags
  # Resolves a flag from the registry, the ENV layer and a snapshot of runtime
  # values, with no I/O: the first layer that is set wins, in the order
  #
  #   ENV > company override > (reserved: rollout %) > global admin value > declared default
  #
  # A company-scoped flag needs `company:` (nil is legal and skips the override
  # step); a global flag refuses one. An undeclared key raises UnknownFlag.
  class Resolver
    def initialize(registry:, env:, snapshot:)
      @registry = registry
      @env = env
      @snapshot = snapshot
    end

    def resolve(key, company: UNSET)
      definition = @registry.fetch(key)
      check_company_argument!(definition, company)

      layers = set_layers(definition, company)
      winner, *shadowed = layers
      Resolution.new(key: definition.key, value: winner[:value], source: winner[:source],
                     env_var: definition.env_var, shadowed: shadowed.reject { |layer| layer[:source] == :default }.freeze)
    end

    private

    def check_company_argument!(definition, company)
      if definition.company_scoped? && company.equal?(UNSET)
        raise ArgumentError, "feature flag #{definition.key} is company-scoped: pass company: " \
                             "(nil when there is no company context)"
      elsif definition.global? && !company.equal?(UNSET)
        raise ArgumentError, "feature flag #{definition.key} is global: do not pass company:"
      end
    end

    def set_layers(definition, company)
      layers = []
      add(layers, :env, @env.value_for(definition.key))
      add(layers, :company, @snapshot.override(definition.key, company.id)) if definition.company_scoped? && !company.nil?
      add(layers, :global, @snapshot.global(definition.key))
      add(layers, :default, definition.default)
      layers.map(&:freeze)
    end

    def add(layers, source, value)
      layers << { source: source, value: value } unless value.nil?
    end
  end
end
