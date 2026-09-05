# frozen_string_literal: true

module Admin
  # Per-scope overrides of the session concurrency cap. Only meaningful while no
  # installation-wide SESSION_CONCURRENCY_LIMIT is configured — with one set,
  # every session draws on the single installation pool and these rows are
  # ignored, which is what the banner on the index says.
  #
  # The defaults these override come from the deployment's environment and are
  # read live, so there is nothing to edit here; the pool mode lives in the
  # policy row and only moves in a maintenance window.
  class SessionConcurrencyLimitsController < Admin::ApplicationController
    def policy
      @policy ||= SessionAdmissionPolicy.current
    end

    def scope_defaults
      @scope_defaults ||= SessionAdmissionPolicy.scope_defaults
    end

    helper_method :policy, :scope_defaults
  end
end
