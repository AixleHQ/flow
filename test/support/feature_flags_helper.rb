# frozen_string_literal: true

# Feature flags in tests. Values are rows: with_feature creates them inside the
# test's transaction, which rolls back on its own. The test cache is a null
# store, so every read goes to the database. Tests use the flags
# config/feature_flags.yml declares: external_runners is company-scoped,
# coder_reap is global and has its own `env:` variable.
#
#   with_feature(:external_runners, true) { ... }                         # global value
#   with_feature(:external_runners, false, company: company) { ... }      # one override
#   stub_feature_env(:coder_reap, "off") { ... }                          # FEATURE_CODER_REAP
#   stub_feature_env(:coder_reap, "off", variable: "CODER_REAP_ENABLED") { ... }   # the flag's env:
#
# An ENV lock is a deployment fact, so it is the one thing a test substitutes:
# stub_feature_env goes through FeatureFlags.with, fiber-local and undone when
# its block ends. A test of the flag machinery itself builds its own Registry,
# EnvSource and Resolver instead.
module FeatureFlagsHelper
  extend ActiveSupport::Concern

  included do
    setup { reset_feature_flags! }
  end

  def reset_feature_flags!
    Current.feature_snapshot = nil
    Feature::REPORTED_UNKNOWN.clear
  end

  def with_feature(key, enabled, company: FeatureFlags::UNSET)
    raise ArgumentError, "with_feature takes true or false, got #{enabled.inspect}" unless [ true, false ].include?(enabled)

    definition = FeatureFlags.registry.fetch(key)
    flag = FeatureFlag.find_or_create_by!(key: definition.key.to_s)
    if company.equal?(FeatureFlags::UNSET)
      previous = flag.enabled
      flag.update!(enabled: enabled)
    else
      raise ArgumentError, "feature flag #{definition.key} is global: it has no company overrides" if definition.global?
      raise ArgumentError, "with_feature(..., company:) needs a company" if company.nil?

      override = flag.overrides.find_or_initialize_by(company: company)
      previous = override.new_record? ? nil : override.enabled
      override.update!(enabled: enabled, reason: "test")
    end

    # A test runs inside one executor run, so the values its first check read
    # would otherwise hide the row written here.
    Current.feature_snapshot = nil
    yield
  ensure
    restore_feature(flag, company, previous) if flag
  end

  # `variable` defaults to FEATURE_<KEY>; pass the flag's own `env:` variable to
  # simulate that one.
  def stub_feature_env(key, value, variable: nil, &)
    definition = FeatureFlags.registry.fetch(key)
    variable ||= definition.env_var
    raise ArgumentError, "#{variable} does not lock #{definition.key}" unless definition.env_vars.include?(variable)

    FeatureFlags.with(env: FeatureFlags.env_source.merge(variable => value), &)
  end

  private

  # Puts the value back when the block ends, so nested with_feature blocks
  # unwind in order; the transaction rollback removes the rows at the end.
  def restore_feature(flag, company, previous)
    if company.equal?(FeatureFlags::UNSET)
      flag.update!(enabled: previous)
    elsif previous.nil?
      flag.overrides.where(company: company).delete_all
    else
      flag.overrides.find_by!(company: company).update!(enabled: previous)
    end
    Current.feature_snapshot = nil
  end
end
