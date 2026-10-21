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
  RELOAD_FAILED_SOURCE = "feature_flags.reload_failed"
  VERSION_BUMP_FAILED_SOURCE = "feature_flags.version_bump_failed"

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

  # A change FeatureFlags::Admin will not make. Nothing was written.
  class WriteRefused < Error; end

  # FEATURE_<KEY> decides the flag in every process, so a runtime value would
  # only look like a change.
  class EnvLocked < WriteRefused
    attr_reader :key, :variable

    def initialize(key, variable)
      @key = key
      @variable = variable
      super("#{key} is locked by #{variable}: change it in the environment and restart")
    end
  end

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
    attr_writer :registry, :env_source, :store, :version_token

    def registry
      @registry ||= Registry.load(REGISTRY_PATH)
    end

    def env_source
      @env_source ||= EnvSource.new(Settings.feature_flags&.env.to_h, registry: registry)
    end

    # The suite replaces this with a MemoryStore before any test runs.
    def store
      @store ||= Store.new(version_token: version_token,
                           refresh_interval: Settings.feature_flags.refresh_interval_seconds,
                           max_staleness: Settings.feature_flags.max_staleness_seconds)
    end

    # Writers call `bump` after their transaction commits.
    def version_token
      @version_token ||= VersionToken.new
    end

    # The first check of a request or job pins the snapshot in Current, so a
    # value changed meanwhile cannot make one page render half old, half new.
    # Rails clears Current when an executor run starts and ends: requests and
    # Active Job executions are runs. Temporal activities are not (the SDK runs
    # them on its own thread pool and Activities::Base adds no executor), so a
    # pin there would outlive the activity on that pool thread: outside a run,
    # each check reads the store's current snapshot instead.
    def snapshot
      return store.snapshot unless Rails.application.executor.active?

      Current.feature_snapshot ||= store.snapshot
    end

    def resolver
      Resolver.new(registry: registry, env: env_source, snapshot: snapshot)
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
