# frozen_string_literal: true

module FeatureFlags
  # What /admin/feature_flags reports for every declared flag, resolved against
  # the rows as committed now rather than the cached values, so an admin sees
  # the change they just made.
  class Overview
    # `resolution` is the value a company without an override gets.
    Row = Data.define(:definition, :flag, :env_value, :env_variable, :resolution, :overrides_on, :overrides_off) do
      def locked? = !env_value.nil?
      # The variable that locks it, or every variable that could.
      def env_vars = locked? ? [ env_variable ] : definition.env_vars
      def global = flag&.enabled
      def past_remove_by?(today = Date.current) = definition.release? && definition.remove_by < today
    end

    attr_reader :resolver

    def initialize(registry: FeatureFlags.registry, env: FeatureFlags.env_source)
      @registry = registry
      @env = env
      @resolver = Resolver.new(registry: registry, env: env, snapshot: FeatureFlag.load_snapshot)
      @flags = FeatureFlag.all.index_by(&:key)
      @counts = FeatureFlagOverride.group(:feature_flag_id, :enabled).count
    end

    def rows = @registry.definitions.sort_by { |definition| definition.key.to_s }.map { |definition| row(definition.key) }

    def row(key)
      definition = @registry.fetch(key)
      flag = @flags[definition.key.to_s]
      resolution = definition.company_scoped? ? @resolver.resolve(key, company: nil) : @resolver.resolve(key)
      Row.new(definition: definition, flag: flag, env_value: @env.value_for(key), env_variable: @env.variable_for(key),
              resolution: resolution, overrides_on: count(flag, true), overrides_off: count(flag, false))
    end

    private

    def count(flag, enabled) = flag ? @counts.fetch([ flag.id, enabled ], 0) : 0
  end
end
