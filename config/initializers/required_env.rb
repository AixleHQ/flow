# frozen_string_literal: true

# Fail fast in every deployed environment (staging included) if critical settings
# are missing. This prevents a misconfigured deploy from serving requests with
# default/empty keys that could silently corrupt encrypted data, or storing uploads
# in a bucket named "fake" (config/settings.yml's fallback).
unless Rails.env.local?
  %w[
    RAILS_SECRET_KEY_BASE
    CREDENTIALS_SECRET_KEY
    CONFIG_ITEMS_SECRET_KEY
    INTEGRATIONS_SECRET_KEY
    OAUTH_SECRET_KEY
    AWS_S3_BUCKET
  ].each do |var|
    raise "Required environment variable #{var} is not set" if ENV[var].blank?
  end
end
