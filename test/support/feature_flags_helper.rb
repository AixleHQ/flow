# frozen_string_literal: true

# Feature flags in tests: no database, no Redis, no real ENV. Every test starts
# from the declared defaults; the helpers below change one layer for a block and
# put it back afterwards.
#
#   with_feature(:board_ai_summary, true) { ... }                          # global value
#   with_feature(:board_ai_summary, false, company: companies(:acme)) { ... }   # one override
#   stub_feature_env(:board_ai_summary, "off") { ... }                     # the FEATURE_* lock
#   with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY) { ... }    # declare test flags
module FeatureFlagsHelper
  extend ActiveSupport::Concern

  EXAMPLE_REGISTRY = Rails.root.join("test/fixtures/files/feature_flags_registry.yml")

  included do
    setup { reset_feature_flags! }
  end

  # Empties the store and the ENV layer, so every test starts from the declared
  # defaults whatever an earlier test or the process environment left behind.
  def reset_feature_flags!
    FeatureFlags.store.reset!
    Feature::REPORTED_UNKNOWN.clear
    FeatureFlags.env_source = FeatureFlags::EnvSource.new({}, registry: FeatureFlags.registry)
  end

  def with_feature(key, enabled, company: FeatureFlags::UNSET)
    raise ArgumentError, "with_feature takes true or false, got #{enabled.inspect}" unless [ true, false ].include?(enabled)

    definition = FeatureFlags.registry.fetch(key)
    store = FeatureFlags.store
    previous = store.snapshot

    if company.equal?(FeatureFlags::UNSET)
      store.set_global(definition.key, enabled)
    else
      raise ArgumentError, "feature flag #{definition.key} is global: it has no company overrides" if definition.global?
      raise ArgumentError, "with_feature(..., company:) needs a company" if company.nil?

      store.set_override(definition.key, company.id, enabled)
    end

    yield
  ensure
    store&.replace(previous) if previous
  end

  def stub_feature_env(key, value)
    definition = FeatureFlags.registry.fetch(key)
    previous = FeatureFlags.env_source
    FeatureFlags.env_source = previous.merge(definition.env_var => value)
    yield
  ensure
    FeatureFlags.env_source = previous if previous
  end

  # Swaps the declared flags (a path or a FeatureFlags::Registry) for the block.
  # The ENV layer is re-read against the new registry.
  def with_feature_registry(registry)
    registry = FeatureFlags::Registry.load(registry) unless registry.is_a?(FeatureFlags::Registry)
    previous_registry = FeatureFlags.registry
    previous_env = FeatureFlags.env_source
    FeatureFlags.registry = registry
    FeatureFlags.env_source = previous_env.with_registry(registry)
    yield
  ensure
    if previous_registry
      FeatureFlags.registry = previous_registry
      FeatureFlags.env_source = previous_env
    end
  end
end
