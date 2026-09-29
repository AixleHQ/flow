# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Digest-stamped assets are public and may be served from the dedicated asset host.
  # Add CORS so module scripts, CSS, fonts, and other static files can be loaded cross-origin.
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}",
    "access-control-allow-origin" => "*"
  }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"
  # Reads the setting, not the variable behind it: the image declares ASSET_HOST
  # as an ENV, so a build without that arg carries it as "" — present as far as
  # the process is concerned, blank as far as anyone means it.
  config.asset_host = Settings.asset_host if Settings.asset_host.present?

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  config.cache_store = :redis_cache_store, { url: Settings.redis.url, namespace: "aixle_cache", expires_in: 1.day }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # Durable jobs. The default in-memory async adapter drops everything queued at
  # the moment a pod restarts, and the invitation mail is the only way a person
  # gets into the product.
  config.active_job.queue_adapter = :solid_queue

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.raise_delivery_errors = true

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding and Host header protection, once the deployment names its hosts
  # (ALLOWED_HOSTS, see config/settings.yml). /up stays open for the kubelet, which
  # probes by pod IP.
  if Settings.app.allowed_hosts.present?
    config.hosts.concat(Settings.app.allowed_hosts)
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end
end
