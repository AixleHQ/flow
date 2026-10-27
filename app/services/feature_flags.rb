# frozen_string_literal: true

# Platform feature flags: declared in config/feature_flags.yml, locked by ENV
# (FEATURE_<KEY>, or a flag's own `env:` variable), set at runtime per company
# or globally. Read them through `Feature.enabled?`; this module holds the
# process-wide parts the facade resolves against.
#
# Guide: docs/architecture/feature-flags.md
module FeatureFlags
  REGISTRY_PATH = Rails.root.join("config/feature_flags.yml")
  CACHE_KEY = "feature_flags/snapshot"
  CACHE_TTL = 10.seconds

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

  # A change FeatureFlags::Admin will not make. Nothing was written.
  class WriteRefused < Error; end

  # An ENV variable decides the flag in every process, so a runtime value would
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

  # What boot! reads once per process: the declared flags and the ENV layer
  # validated against them.
  Graph = Data.define(:registry, :env_source)

  # The fiber-local slot FeatureFlags.with fills for the length of its block.
  SCOPED_ENV = :feature_flags_scoped_env

  class << self
    def registry = booted.registry
    def env_source = Thread.current[SCOPED_ENV] || booted.env_source

    # TEST SEAM: production code must not call this. Resolves every check made
    # on this fiber inside the block against `env` (an EnvSource) instead of the
    # booted ENV layer. Reached through stub_feature_env
    # (test/support/feature_flags_helper.rb), not directly.
    def with(env:)
      previous = Thread.current[SCOPED_ENV]
      Thread.current[SCOPED_ENV] = env
      yield
    ensure
      Thread.current[SCOPED_ENV] = previous
    end

    # The runtime values, read once per request or job: the memo in Current
    # gives one unit of work one answer per flag. Rails resets Current when an
    # executor run starts and ends; Temporal activities run outside one, so
    # there each check reads the cache.
    def snapshot
      return load_snapshot unless Rails.application.executor.active?

      Current.feature_snapshot ||= load_snapshot
    end

    # Rails.cache is the shared Redis: a write deletes the key (changed!), so
    # every process reads the change next; the TTL covers a delete that never
    # reached Redis. With Redis down the cache store reads the database.
    def load_snapshot = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { FeatureFlag.load_snapshot }

    # Called by FeatureFlags::Admin after its transaction commits.
    def changed! = Rails.cache.delete(CACHE_KEY)

    def resolver = Resolver.new(registry: registry, env: env_source, snapshot: snapshot)

    # A `client: true` flag as the `features` shared prop (FeaturesResource)
    # sends it to a browser. `company: nil` (an anonymous page) reads a
    # company-scoped flag at its global value; a global flag is read without
    # the company, which would raise.
    def client_value(definition, company:)
      definition.company_scoped? ? Feature.enabled?(definition.key, company: company) : Feature.enabled?(definition.key)
    end

    # Composes the graph and installs it for the process. A test of composition
    # calls #compose.
    def boot!(**options) = @booted = compose(**options)

    # The installed graph, composed on first use. config/initializers/feature_flags.rb
    # calls it after initialization; eager loading or a rake task may reach it
    # first, and the graph is composed (and undeclared variables reported) once.
    def booted = @booted || boot!

    # Loads and validates the registry and the ENV layer, raising on anything
    # invalid, reports FEATURE_* variables no flag declares, and returns the
    # graph without installing it.
    def compose(registry_path: REGISTRY_PATH, env: Settings.feature_flags&.env.to_h)
      registry = Registry.load(registry_path)
      env_source = EnvSource.new(env, registry: registry)
      report_undeclared(env_source)
      Graph.new(registry: registry, env_source: env_source)
    end

    private

    def report_undeclared(env_source)
      env_source.undeclared.each do |variable|
        error = UndeclaredEnv.new(variable)
        Rails.logger.warn("[FeatureFlags] #{error.message}")
        Rails.error.report(error, handled: true, severity: :warning, source: UNDECLARED_ENV_SOURCE,
                                  context: { variable: variable })
      end
    end
  end
end
