require_relative "production"

Rails.application.configure do
  # Staging currently follows production defaults unless explicitly overridden here.
  config.log_level = :debug
end
