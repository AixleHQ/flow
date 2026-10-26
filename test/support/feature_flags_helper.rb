# frozen_string_literal: true

require_relative "fakes/fake_feature_flag_version_token"

# Feature flags in tests: no database, no Redis, no real ENV. Every test starts
# from the declared defaults; the helpers below change one layer for a block and
# put it back afterwards.
#
#   with_feature(:board_ai_summary, true) { ... }                          # global value
#   with_feature(:board_ai_summary, false, company: companies(:acme)) { ... }   # one override
#   stub_feature_env(:board_ai_summary, "off") { ... }                     # the FEATURE_* lock
#   stub_feature_env_setting(:coder_reap, false) { ... }                   # the legacy env_setting lock
#   with_feature_registry(FeatureFlagsHelper::EXAMPLE_REGISTRY) { ... }    # declare test flags
#
# Values are the normal lever: with_feature writes the memory store, the same
# mechanism production uses. The ENV and registry helpers go through the one
# test seam, FeatureFlags.with, so a substitution is fiber-local and ends with
# its block. A test of registry, ENV or resolver semantics builds those objects
# itself (FeatureFlags::Resolver.new(registry:, env:, snapshot:)) instead.
#
# The database-backed FeatureFlags::Store is tested on its own, against real
# rows and its own FakeFeatureFlagVersionToken (test/services/feature_flags/store_test.rb).
module FeatureFlagsHelper
  extend ActiveSupport::Concern

  EXAMPLE_REGISTRY = Rails.root.join("test/fixtures/files/feature_flags_registry.yml")

  included do
    setup { reset_feature_flags! }
  end

  class_methods do
    # with_feature_registry around every test of the class, setup and teardown included.
    def uses_feature_registry(path)
      registry = FeatureFlags::Registry.load(path)
      prepend(Module.new do
        define_method(:run) { with_feature_registry(registry) { super() } }
      end)
    end
  end

  # Empties the store and resets the version token, so every test starts from
  # the declared defaults and counts its own bumps whatever an earlier test left
  # behind. The ENV layer needs no reset: it is the booted one, empty in the
  # suite, outside any stub_feature_env block.
  def reset_feature_flags!
    FeatureFlags.store.reset!
    FeatureFlags.version_token.reset!
    Current.feature_snapshot = nil
    Feature::REPORTED_UNKNOWN.clear
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

    # A test runs inside one executor run, so the snapshot its first check
    # pinned would otherwise hide the value set here.
    Current.feature_snapshot = nil
    yield
  ensure
    if previous
      store.replace(previous)
      Current.feature_snapshot = nil
    end
  end

  def stub_feature_env(key, value, &)
    definition = FeatureFlags.registry.fetch(key)
    FeatureFlags.with(env: FeatureFlags.env_source.merge(definition.env_var => value), &)
  end

  # The legacy lock of a flag declared with env_setting: `value` is what
  # config/settings.yml would give it (true or false when its variable is set,
  # nil when it is not).
  def stub_feature_env_setting(key, value, &)
    definition = FeatureFlags.registry.fetch(key)
    raise ArgumentError, "feature flag #{definition.key} declares no env_setting" if definition.env_setting.nil?

    FeatureFlags.with(env: FeatureFlags.env_source.merge_settings(definition.env_setting => value), &)
  end

  # Swaps the declared flags (a path or a FeatureFlags::Registry) for the block.
  # The ENV layer is re-read against the new registry.
  def with_feature_registry(registry, &)
    registry = FeatureFlags::Registry.load(registry) unless registry.is_a?(FeatureFlags::Registry)
    FeatureFlags.with(registry: registry, &)
  end
end

# The test environment's infrastructure, composed once for the whole suite:
# CI has no Redis, and the suite never reads flag values from the database, so
# the store is a MemoryStore and the version token a fake. The ENV layer is
# empty: config/settings/test.yml drops FEATURE_* variables, and `settings: nil`
# keeps legacy env_setting variables (CODER_REAP_ENABLED) of the shell out.
# Parallel workers fork after this and each keeps its own copy.
FeatureFlags.boot!(settings: nil, store: FeatureFlags::MemoryStore.new, version_token: FakeFeatureFlagVersionToken.new)
