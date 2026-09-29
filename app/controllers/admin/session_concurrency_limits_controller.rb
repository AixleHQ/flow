# frozen_string_literal: true

module Admin
  # The raw limit rows, both tiers. A Company row is what the installation sells
  # and bills for; a Project row is a RESERVATION drawn from it — that project
  # can always reach its number, and every project without a row shares what the
  # reservations leave of the company's limit.
  #
  # This is the unfiltered table. A company's limit is normally set on the
  # company's own page, and a project's from the project's settings by a company
  # admin. The default a project row overrides comes from the deployment's
  # environment and is read live, so there is nothing to edit here.
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
