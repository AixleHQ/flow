running_console = Rails.const_defined?("Console")

Sentry.init do |config|
  config.dsn = Settings.sentry.rails_dsn
  config.release = Settings.app.version
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = true
  config.enable_logs = !running_console
  config.enabled_patches = running_console ? [] : [ :logger ]
  config.traces_sample_rate = 1.0
  config.traces_sampler = lambda do |context|
    true
  end
  config.profiles_sample_rate = 1.0
end
