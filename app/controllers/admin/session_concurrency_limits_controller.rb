# frozen_string_literal: true

module Admin
  # Per-scope overrides of the session concurrency cap. Only meaningful while no
  # installation-wide SESSION_CONCURRENCY_LIMIT is configured — with one set,
  # every session draws on the single installation pool and these rows are
  # ignored, which is what the banner on the index says.
  #
  # The defaults these override (project_default, user_default) and the pool mode
  # itself are deployment configuration, written by `session_admission:sync`, and
  # are deliberately read-only here: a value edited in the UI would be silently
  # reverted by the next deploy's sync.
  class SessionConcurrencyLimitsController < Admin::ApplicationController
    def policy
      @policy ||= SessionAdmissionPolicy.current
    end
    helper_method :policy
  end
end
