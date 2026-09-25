# frozen_string_literal: true

# One Sentry configuration for every process. The web app initializes it here;
# bin/temporal_worker re-initializes with its own DSN through the same module —
# a second, hand-written Sentry.init is how the worker once ran 100% profiling
# and, another time, crashed on a removed option nobody updated there.
module SentryConfiguration
  # The telemetry ingest endpoint. Agent runtimes POST an OTLP envelope here every
  # couple of seconds for every live session, so it is by far the busiest route in
  # the app and by far the least interesting one to observe: it has no user, no
  # view, and one code path. Tracing and breadcrumbing it cost more than they tell.
  USAGE_INGEST_PATH = "/api/v1/internal/usage_statistics"
  USAGE_INGEST_CONTROLLER = "Api::V1::Internal::UsageStatisticsController"

  # Request headers that authenticate someone; never sent.
  SENSITIVE_HEADERS = %w[Authorization Cookie X-Session-Key X-Agent-Key X-Cloud-Key X-Azure-Git-Key X-Git-Key].freeze

  module_function

  def apply(config, dsn:)
    running_console = Rails.const_defined?("Console")

    config.dsn = dsn
    config.release = Settings.app.version
    config.environment = Rails.env
    config.enabled_environments = %w[production staging]
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    # A non-zero `exit` from `rails runner`/`rails db:*` unwinds as SystemExit and lands in
    # Sentry as an unhandled crash in `bin/rails`. The exit status is the signal to whatever
    # ran the command; it says nothing about the app, and it carries no useful stacktrace.
    config.excluded_exceptions += %w[SystemExit]

    # Off: with it on, events carry the raw request body, every cookie (the Rails
    # session among them) and the Authorization header, and spans carry the
    # UNFILTERED params — passwords, config-item values, MCP headers, OAuth codes.
    config.send_default_pii = false

    # sentry-ruby 7 removed `enable_logs` — logs are unconditionally on. Rails
    # structured logging is set to what 6.7 derived from it, so a `rails console`
    # still ships nothing and the web/worker processes keep their subscribers.
    config.rails.structured_logging.enabled = !running_console
    # Added to the defaults rather than replacing them: `[:logger]` alone silently
    # turned off the redis, puma and outbound-HTTP instrumentation.
    config.enabled_patches += [ :logger ] unless running_console

    rate = Settings.sentry.traces_sample_rate.to_f
    config.traces_sampler = lambda do |context|
      path = context.dig(:env, "PATH_INFO") || context.dig(:env, :PATH_INFO)
      next false if path.to_s.start_with?(USAGE_INGEST_PATH)

      rate
    end

    # Was 1.0, which started and stopped a profiler on every single request. Most of
    # them were too short to yield anything: a production web log showed 67 profiles
    # started against 36 that logged "Not enough samples, discarding profiler" — more
    # than half the work thrown away at the end. Profile a slice instead, and only
    # inside traces that were sampled in the first place.
    config.profiles_sample_rate = 0.05

    # The active_support_logger breadcrumb carries the controller's params, which
    # on the ingest route is the entire OTLP envelope — Sentry could not even
    # serialise it ("nesting of 10 is too deep", once per request).
    config.before_breadcrumb = lambda do |breadcrumb, _hint|
      data = breadcrumb.data
      next breadcrumb unless data.is_a?(Hash)

      controller = data[:controller] || data["controller"]
      next breadcrumb unless controller.to_s == USAGE_INGEST_CONTROLLER

      breadcrumb.data = data.except(:params, "params").merge(params: "[FILTERED]")
      breadcrumb
    end

    config.before_send = ->(event, _hint) { scrub_request(event) }
    config.before_send_transaction = ->(event, _hint) { scrub_request(event) }
  end

  # Belt and braces over send_default_pii: whatever request data an event still
  # carries goes through the same parameter filter the Rails logs use.
  def scrub_request(event)
    request = event.request
    return event unless request

    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    request.data = filter.filter(request.data) if request.data.is_a?(Hash)
    request.cookies = {} if request.respond_to?(:cookies=)
    if request.headers.is_a?(Hash)
      request.headers = request.headers.reject { |name, _| SENSITIVE_HEADERS.any? { |h| h.casecmp?(name.to_s) } }
    end
    event
  end
end

Sentry.init { |config| SentryConfiguration.apply(config, dsn: Settings.sentry.rails_dsn) }

# sentry-rails leaves `register_error_subscriber` off, so a `Rails.error.report` reaches
# Sentry only from a source listed here. Turning the global subscriber on instead would
# also forward everything Rails itself reports through the executor.
forwarded_error_sources = {
  # One issue per runtime and failure mode, not one per credential.
  "agent_credential.refresh" => ->(context) {
    [ "agent_credential.refresh", context[:agent_type], context[:refresh_source],
      context[:permanent] ? "permanent" : "transient" ]
  }
}.freeze

Rails.error.subscribe(Class.new do
  define_method(:report) do |error, handled:, severity:, context:, source: nil|
    fingerprint = forwarded_error_sources[source]
    next if fingerprint.nil? || !Sentry.initialized?

    Sentry.with_scope do |scope|
      scope.set_tags(context.except(:credential_id, :failure_count).transform_values(&:to_s))
      scope.set_context("report", context)
      scope.set_fingerprint(fingerprint.call(context))
      scope.set_level(severity)
      Sentry.capture_exception(error)
    end
  end
end.new)
