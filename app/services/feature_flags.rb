# frozen_string_literal: true

# Platform feature flags: declared in config/feature_flags.yml, locked by
# FEATURE_<KEY>, set at runtime per company or globally. Read them through
# `Feature.enabled?`; this module holds the process-wide parts the facade
# resolves against.
#
# Design: docs/research/technical-feature-flags-system-design-research-2026-10-21.md
module FeatureFlags
  REGISTRY_PATH = Rails.root.join("config/feature_flags.yml")

  # Distinguishes "company: nil" (no company context, legal) from a call that
  # left the keyword out (a forgotten tenant, which raises).
  UNSET = Object.new.tap { |unset| def unset.inspect = "FeatureFlags::UNSET" }.freeze

  UNKNOWN_FLAG_SOURCE = "feature_flags.unknown_flag"
  UNDECLARED_ENV_SOURCE = "feature_flags.undeclared_env"

  class Error < StandardError; end

  # A key the registry does not declare: a typo, or a call left behind after
  # the flag was removed.
  class UnknownFlag < Error
    attr_reader :key

    def initialize(key)
      @key = key
      super("feature flag #{key.inspect} is not declared in config/feature_flags.yml")
    end
  end

  class InvalidRegistry < Error; end
  class InvalidEnv < Error; end

  # A FEATURE_* variable for a key the registry does not declare. Reported, never raised.
  class UndeclaredEnv < Error
    attr_reader :variable

    def initialize(variable)
      @variable = variable
      super("#{variable} is set but no flag #{variable.delete_prefix(EnvSource::PREFIX).downcase} " \
            "is declared in config/feature_flags.yml; it is ignored")
    end
  end

  class << self
    # Test seams: the suite swaps these through test/support/feature_flags_helper.rb.
    attr_writer :registry, :env_source, :store

    def registry
      @registry ||= Registry.load(REGISTRY_PATH)
    end

    def env_source
      @env_source ||= EnvSource.new(Settings.feature_flags&.env.to_h, registry: registry)
    end

    # Only the in-memory store exists until the database-backed one lands, so
    # every flag resolves from ENV and its declared default.
    def store
      @store ||= MemoryStore.new
    end

    def resolver
      Resolver.new(registry: registry, env: env_source, snapshot: store.snapshot)
    end

    # Loads and validates the registry and the ENV layer, raising on anything
    # invalid, and reports FEATURE_* variables no flag declares.
    def boot!(registry_path: REGISTRY_PATH, env: Settings.feature_flags&.env.to_h)
      self.registry = Registry.load(registry_path)
      self.env_source = EnvSource.new(env, registry: registry)

      env_source.undeclared.each do |variable|
        error = UndeclaredEnv.new(variable)
        Rails.logger.warn("[FeatureFlags] #{error.message}")
        Rails.error.report(error, handled: true, severity: :warning, source: UNDECLARED_ENV_SOURCE,
                                  context: { variable: variable })
      end
    end
  end
end
