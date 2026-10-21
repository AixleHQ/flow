# frozen_string_literal: true

module FeatureFlags
  # What /admin/feature_flags reports for every declared flag, and the rows no
  # flag declares any more.
  #
  # Resolved against the rows as committed now, not this process's snapshot:
  # that can lag a write by the store's refresh interval (its max staleness
  # while Redis is down), and an admin must see the change they just made.
  class Overview
    SAME_EVERYWHERE_FOR = 30.days

    # `resolution` is the value a company without an override gets.
    Row = Data.define(:definition, :flag, :env_value, :resolution, :overrides_on, :overrides_off) do
      def key = definition.key
      def locked? = !env_value.nil?
      def global = flag&.enabled
      def overrides_count = overrides_on + overrides_off
      def past_remove_by?(today = Date.current) = !definition.remove_by.nil? && definition.remove_by < today

      # The date since which every company gets one value, or nil when an
      # override differs or nothing says how long it has been. Every admin write
      # touches the flag's row; a flag with no row has had its default since
      # it was introduced.
      def same_everywhere_since
        differing = resolution.value ? overrides_off : overrides_on
        return if !locked? && definition.company_scoped? && differing.positive?

        flag ? flag.updated_at.to_date : definition.introduced
      end

      def same_everywhere_long?(today = Date.current)
        since = same_everywhere_since
        !since.nil? && since <= today - SAME_EVERYWHERE_FOR
      end
    end

    Orphan = Data.define(:flag, :overrides_count) do
      def key = flag.key
    end

    def initialize(registry: FeatureFlags.registry, env: FeatureFlags.env_source)
      @registry = registry
      @env = env
      @resolver = Resolver.new(registry: registry, env: env, snapshot: FeatureFlag.load_snapshot)
      @flags = FeatureFlag.all.index_by(&:key)
      @counts = FeatureFlagOverride.group(:feature_flag_id, :enabled).count
    end

    attr_reader :resolver

    def rows = @registry.definitions.sort_by { |definition| definition.key.to_s }.map { |definition| row_for(definition) }

    def row(key) = row_for(@registry.fetch(key))

    def orphans
      @flags.values.reject { |flag| @registry.declared?(flag.key) }.sort_by(&:key).map do |flag|
        Orphan.new(flag: flag, overrides_count: count(flag, true) + count(flag, false))
      end
    end

    private

    def row_for(definition)
      flag = @flags[definition.key.to_s]
      resolution = definition.company_scoped? ? @resolver.resolve(definition.key, company: nil) : @resolver.resolve(definition.key)
      Row.new(definition: definition, flag: flag, env_value: @env.value_for(definition.key), resolution: resolution,
              overrides_on: count(flag, true), overrides_off: count(flag, false))
    end

    def count(flag, enabled) = flag ? @counts.fetch([ flag.id, enabled ], 0) : 0
  end
end
