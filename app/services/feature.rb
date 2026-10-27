# frozen_string_literal: true

# Reads platform feature flags (config/feature_flags.yml).
#
#   Feature.enabled?(:external_runners, company: current_company)  # company-scoped; nil is legal
#   Feature.enabled?(:coder_reap)                                   # global; company: raises
#   Feature.explain(:external_runners, company: company)            # value, source, ENV variable
#
# Deliberately no `disabled?`, setter or block form: an `if Feature.enabled?`
# is the one shape to search for when a flag is removed.
module Feature
  # Undeclared keys already reported by this process.
  REPORTED_UNKNOWN = Concurrent::Set.new

  class << self
    def enabled?(key, company: FeatureFlags::UNSET) = explain(key, company: company).value

    # An undeclared key raises in development and test. Elsewhere it reads as
    # off and is reported once per process, so a typo that slipped through is
    # not a 500 and a check on a hot path does not send an event per request.
    def explain(key, company: FeatureFlags::UNSET)
      FeatureFlags.resolver.resolve(key, company: company)
    rescue FeatureFlags::UnknownFlag => e
      raise if Rails.env.local?

      if REPORTED_UNKNOWN.add?(key.to_s)
        Rails.error.report(e, handled: true, severity: :error, source: FeatureFlags::UNKNOWN_FLAG_SOURCE,
                              context: { flag: key.to_s })
      end
      FeatureFlags::Resolution.unknown(key)
    end
  end
end
