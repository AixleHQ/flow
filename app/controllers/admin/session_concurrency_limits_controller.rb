# frozen_string_literal: true

module Admin
  # Per-project overrides of the session concurrency cap. Each row is a
  # RESERVATION: that project can always reach its number, and every project
  # without a row shares what the reservations leave of
  # SESSION_CONCURRENCY_LIMIT. They used to be ignored whenever an
  # installation-wide limit was set, because it selected a single pool instead;
  # it is a ceiling these are drawn from now, so both apply at once.
  #
  # The default a row overrides comes from the deployment's environment and is
  # read live, so there is nothing to edit here. A company admin can set the same
  # value from the project's own settings.
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
