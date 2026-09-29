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

  # Opening self-serve signup without a way to take payment is a trap that only
  # springs later: people sign up, spend the free allowance, and reach a stop
  # with no card to add and no button to press. The two switches must not be
  # able to drift apart, so the deploy refuses rather than the customers finding
  # out. Checked here and not in Deployment, because a key that goes missing
  # must fail loudly rather than quietly closing the door on new customers.
  if Deployment.self_serve_signup? && !Billing::StripeClient.new.configured?
    raise "REGISTRATION_ENABLED is on but Stripe is not configured: set STRIPE_SECRET_KEY and " \
          "STRIPE_PRICE_ID, or close registration. A workspace that signs itself up spends its free " \
          "capacity and then has nowhere to pay."
  end
end
