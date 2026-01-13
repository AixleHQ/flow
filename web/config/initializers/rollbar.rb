Rollbar.configure do |config|
  config.environment = Rails.env
  config.access_token = Settings.rollbar.access_token
  config.code_version = Settings.app.version
  config.enabled = !Rails.env.local?

  config.exception_level_filters.merge!(
    {
      "ActionController::RoutingError" => "ignore"
    }
  )
end
