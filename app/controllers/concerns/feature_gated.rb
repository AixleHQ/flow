# frozen_string_literal: true

# Declares that a controller, or some of its actions, exists only while a
# feature flag is on (docs/architecture/feature-flags.md). Anything else
# answers 404, as if the route were not there.
#
#   class Web::Company::RunnersController < Web::Company::ApplicationController
#     requires_feature :external_runners                   # every action
#     requires_feature :runner_tokens, only: %i[rotate]    # some actions
#   end
#
# The check is prepended, so it runs ahead of authentication and authorization,
# and a company without the flag gets the same 404 whatever the user's role. A
# company-scoped flag is read for `current_company` when a user is signed in.
# Without a session (an anonymous visitor, or a token-authenticated controller)
# there is no company, so the flag is read at its global value, as
# FeatureFlags.client_value does for anonymous pages: the gate fails closed
# rather than letting the request through. A global flag is read for every
# request.
module FeatureGated
  extend ActiveSupport::Concern

  class_methods do
    # `options` are the before_action filters (`only:`, `except:`, `if:`,
    # `unless:`). Keep `key` a literal symbol: it is what to search for when
    # the flag is removed.
    def requires_feature(key, **options)
      prepend_before_action(**options) { head :not_found unless required_feature_enabled?(key) }
    end
  end

  private

  def required_feature_enabled?(key)
    # An undeclared key goes to Feature.enabled? as it is, which raises in
    # development and test and reads as off elsewhere.
    return Feature.enabled?(key) unless FeatureFlags.registry.declared?(key)

    FeatureFlags.client_value(FeatureFlags.registry.fetch(key), company: signed_in? ? current_company : nil)
  end
end
