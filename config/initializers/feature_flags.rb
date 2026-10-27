# frozen_string_literal: true

# An invalid config/feature_flags.yml or FEATURE_* value fails boot here, not on
# the first request that checks the flag. After initialization because
# FeatureFlags lives in app/ and is not autoloadable from an initializer.
# `booted`, not `boot!`: eager loading (FeaturesResource reads the registry in
# its class body) may already have composed the graph, and composing again would
# report every undeclared FEATURE_* variable a second time.
Rails.application.config.after_initialize do
  FeatureFlags.booted
end
