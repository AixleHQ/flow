# frozen_string_literal: true

module FeatureFlags
  # Resolves a flag from the registry, the ENV layer and a snapshot of runtime
  # values (FeatureFlag.load_snapshot), with no I/O: the first layer that is set
  # wins, in the order
  #
  #   ENV > company override > global admin value > declared default
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

      source, value = layers(definition, company).find { |_, layer_value| !layer_value.nil? }
      Resolution.new(key: definition.key, value: value, source: source,
                     env_var: @env.variable_for(definition.key) || definition.env_var)
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

    def layers(definition, company)
      values = @snapshot.fetch(definition.key, {})
      override = values.dig(:overrides, company.id) if definition.company_scoped? && !company.nil?
      { env: @env.value_for(definition.key), company: override, global: values[:global], default: definition.default }
    end
  end
end
