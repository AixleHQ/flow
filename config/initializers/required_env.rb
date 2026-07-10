# frozen_string_literal: true

# Fail fast in production if critical secrets are missing.
# This prevents a misconfigured deploy from serving requests with
# default/empty keys that could silently corrupt encrypted data.
if Rails.env.production?
  %w[
    RAILS_SECRET_KEY_BASE
    CREDENTIALS_SECRET_KEY
    CONFIG_ITEMS_SECRET_KEY
    INTEGRATIONS_SECRET_KEY
    OAUTH_SECRET_KEY
  ].each do |var|
    raise "Required environment variable #{var} is not set" if ENV[var].blank?
  end
end
