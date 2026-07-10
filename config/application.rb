require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

def default_options
  { host: Settings.domain, protocol: Settings.protocol }
end

module Aixle
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    config.require_master_key = false
    config.secret_key_base = Settings.rails.secret_key_base
    config.public_file_server.enabled = true

    config.middleware.use Rack::Attack

    # Drop the X-Runtime header — it exposes per-request server processing time
    # (a timing side-channel / fingerprinting aid) for no operational benefit (F4).
    config.middleware.delete Rack::Runtime

    # Set Sidekiq as the job processor
    # config.active_job.queue_adapter = :sidekiq

    config.autoload_paths += [ Rails.root.join("config", "routes") ]
    config.eager_load_paths += [ Rails.root.join("config", "routes") ]

    config.lograge.enabled = true
    config.lograge.ignore_actions = [
      "Rails::HealthController#show"
      # "Api::V1::Internal::WsAuthController#show"
    ]
    config.lograge.custom_options = lambda do |event|
      return if event.name.include?("action_cable")
      return if event.payload[:path]&.start_with?("/mcp")

      {
        host: event.payload[:host],
        ip: event.payload[:ip],
        ff: event.payload[:ff],
        user: event.payload[:user],
        params: event.payload[:params].except("controller", "action", "format", "utf8")
      }
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.generators do |g|
      g.template_engine :haml
      g.stylesheets false
      g.javascripts false
      g.helper false
      g.test_framework :test_unit, fixture: false
      g.factory_bot true
    end

    # config.action_controller.default_url_options = default_options
    config.action_mailer.default_url_options = default_options
    config.default_url_options = default_options

    config.action_mailer.smtp_settings = {
      address: Settings.mailer.address,
      port: Settings.mailer.port,
      domain: Settings.mailer.domain,
      user_name: Settings.mailer.user_name,
      password: Settings.mailer.password,
      authentication: Settings.mailer.authentication,
      enable_starttls_auto: true
    }

    if ENV["RAILS_LOG_TO_STDOUT"].present?
      logger = ActiveSupport::Logger.new(STDOUT)
      logger.formatter = config.log_formatter
      config.logger = ActiveSupport::TaggedLogging.new(logger)
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
