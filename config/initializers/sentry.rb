running_console = Rails.const_defined?("Console")

# The telemetry ingest endpoint. Agent runtimes POST an OTLP envelope here every
# couple of seconds for every live session, so it is by far the busiest route in
# the app and by far the least interesting one to observe: it has no user, no
# view, and one code path. Tracing and breadcrumbing it cost more than they tell.
# Locals rather than constants — the lambdas below close over them, and an
# initializer has no business adding names to Object.
usage_ingest_path = "/api/v1/internal/usage_statistics"
usage_ingest_controller = "Api::V1::Internal::UsageStatisticsController"

Sentry.init do |config|
  config.dsn = Settings.sentry.rails_dsn
  config.release = Settings.app.version
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  # A non-zero `exit` from `rails runner`/`rails db:*` unwinds as SystemExit and lands in
  # Sentry as an unhandled crash in `bin/rails`. The exit status is the signal to whatever
  # ran the command; it says nothing about the app, and it carries no useful stacktrace.
  config.excluded_exceptions += %w[SystemExit]
  config.send_default_pii = true
  config.enable_logs = !running_console
  config.enabled_patches = running_console ? [] : [ :logger ]
  config.traces_sample_rate = 1.0
  config.traces_sampler = lambda do |context|
    path = context.dig(:env, "PATH_INFO") || context.dig(:env, :PATH_INFO)

    next false if path.to_s.start_with?(usage_ingest_path)

    true
  end

  # Was 1.0, which started and stopped a profiler on every single request. Most of
  # them were too short to yield anything: a production web log showed 67 profiles
  # started against 36 that logged "Not enough samples, discarding profiler" — more
  # than half the work thrown away at the end. Profile a slice instead, and only
  # inside traces that were sampled in the first place.
  config.profiles_sample_rate = 0.05

  # The active_support_logger breadcrumb carries the controller's raw params, which
  # on the ingest route is the entire OTLP envelope. Sentry could not even serialise
  # it — production logged "can't serialize breadcrumb data because of error:
  # nesting of 10 is too deep" once per request — so the payload bought nothing and
  # was rebuilt in memory every time regardless.
  config.before_breadcrumb = lambda do |breadcrumb, _hint|
    data = breadcrumb.data
    next breadcrumb unless data.is_a?(Hash)

    controller = data[:controller] || data["controller"]
    next breadcrumb unless controller.to_s == usage_ingest_controller

    breadcrumb.data = data.except(:params, "params").merge(params: "[FILTERED]")
    breadcrumb
  end
end
