# frozen_string_literal: true

# Initialize SolidMCP message writer
Rails.application.config.to_prepare do
  # Ensure the writer thread is started
  SolidMCP::MessageWriter.instance
end

# Gracefully shutdown on exit
at_exit do
  SolidMCP::MessageWriter.instance.shutdown if defined?(SolidMCP::MessageWriter)
rescue NoMethodError
  # SolidMCP::Logger may reference a nil logger during shutdown
end

# Configure SolidMCP
SolidMCP.configure do |config|
  config.batch_size = 200
  config.flush_interval = 0.05
  config.delivered_retention = 1.hour
  config.undelivered_retention = 24.hours
end
