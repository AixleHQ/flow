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

  # The process-wide parts, composed once by boot!: the declared flags, the ENV
  # layer validated against them, the store of runtime values and the token
  # writers bump. They reference each other (the ENV layer holds the registry),
  # so they are built, and in tests substituted, as one unit.
  Graph = Data.define(:registry, :env_source, :store, :version_token)

  # The fiber-local slot FeatureFlags.with fills for the length of its block.
  SCOPED_GRAPH = :feature_flags_scoped_graph

  class << self
    # Read-only: the graph is composed by boot!, and a test substitutes the
    # registry or the ENV layer for a block with FeatureFlags.with.
    def registry = graph.registry
    def env_source = graph.env_source

    # Never substituted per block: they are infrastructure, chosen by whoever
    # calls boot! (the suite passes a MemoryStore and a fake token).
    def store = booted.store

    # Writers call `bump` after their transaction commits.
    def version_token = booted.version_token

    # TEST SEAM: production code must not call this. Resolves every check made
    # on this fiber inside the block against `registry:` and/or `env:` (an
    # EnvSource) instead of the booted ones, and drops the substitution when the
    # block exits, however it exits. A registry without `env:` gets the current
    # ENV layer re-read against it, as the ENV layer holds the registry it was
    # validated with. The store and the version token are never substituted.
    #
    # The substitution is fiber-local: another thread (a Capybara server, a
    # thread a test spawns) and a Temporal activity, which the SDK runs on its
    # own pool thread (see #snapshot), see the booted graph. So nothing that runs
    # or memoises elsewhere while the block is active can pick the test registry up.
    #
    # The suite reaches it through test/support/feature_flags_helper.rb
    # (with_feature_registry, stub_feature_env, ...), not directly.
    def with(registry: nil, env: nil)
      raise ArgumentError, "FeatureFlags.with needs a block" unless block_given?
      raise ArgumentError, "FeatureFlags.with needs registry: or env:" if registry.nil? && env.nil?

      current = graph
      env_source = env || current.env_source
      env_source = env_source.with_registry(registry) unless registry.nil?
      scoped = current.with(registry: registry || current.registry, env_source: env_source)

      previous = Thread.current[SCOPED_GRAPH]
      begin
        Thread.current[SCOPED_GRAPH] = scoped
        yield
      ensure
        Thread.current[SCOPED_GRAPH] = previous
      end
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

    # The `features` shared prop: the resolved value of every flag declared
    # `client: true`, and of nothing else, so internal and ops flag names never
    # reach a browser. Resolved through Feature like any backend check, so a
    # company's override is what that company's pages see. `company: nil` (an
    # anonymous page) reads company-scoped flags at their global value.
    def client_payload(company:)
      registry.definitions.select(&:client?).to_h do |definition|
        value = if definition.company_scoped?
          Feature.enabled?(definition.key, company: company)
        else
          Feature.enabled?(definition.key)
        end
        [ definition.key, value ]
      end
    end

    # The one composition entry point: composes the graph and installs it for
    # the process. Called by config/initializers/feature_flags.rb, and once more
    # by the suite's global setup with its infrastructure (test/support/feature_flags_helper.rb).
    def boot!(...)
      @booted = compose(...)
    end

    # Loads and validates the registry and the ENV layer (FEATURE_* and the
    # legacy env_setting values in `settings`), raising on anything invalid,
    # reports FEATURE_* variables no flag declares, and returns the graph
    # without installing it. `store:` and `version_token:` default to the
    # database-backed store and the Redis token.
    def compose(registry_path: REGISTRY_PATH, env: Settings.feature_flags&.env.to_h, settings: Settings.to_h,
                store: nil, version_token: nil)
      registry = Registry.load(registry_path)
      env_source = EnvSource.new(env, registry: registry, settings: settings)
      report_undeclared(env_source)

      version_token ||= VersionToken.new
      store ||= Store.new(version_token: version_token,
                          refresh_interval: Settings.feature_flags.refresh_interval_seconds,
                          max_staleness: Settings.feature_flags.max_staleness_seconds)
      Graph.new(registry: registry, env_source: env_source, store: store, version_token: version_token)
    end

    private

    def graph = Thread.current[SCOPED_GRAPH] || booted

    # boot! runs after initialization; a read before it (an initializer, a
    # rake task loading app code early) composes the default graph.
    def booted = @booted || boot!

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
