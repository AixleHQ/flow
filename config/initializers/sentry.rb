running_console = Rails.const_defined?("Console")

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
    true
  end
  config.profiles_sample_rate = 1.0
end
