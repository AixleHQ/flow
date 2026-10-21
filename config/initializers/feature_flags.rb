# frozen_string_literal: true

# An invalid config/feature_flags.yml or FEATURE_* value fails boot here, not on
# the first request that checks the flag. After initialization because
# FeatureFlags lives in app/ and is not autoloadable from an initializer.
Rails.application.config.after_initialize do
  FeatureFlags.boot!
end
