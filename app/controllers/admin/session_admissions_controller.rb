# frozen_string_literal: true

module Admin
  # What the session queue resolves to right now. Nothing here changes it:
  # limits are company rows for what was sold and project rows for how it was
  # divided, and admission itself is always on.
  class SessionAdmissionsController < Admin::ApplicationController
    def show
      @scope_defaults = SessionAdmissionPolicy.scope_defaults
      @reserved_total = SessionConcurrencyLimit.for_projects.sum(:max_sessions)
      @company_limits = SessionConcurrencyLimit.for_companies.order(:scope_id)
      @overcommitted = SessionConcurrencyLimit.overcommitted_companies
      @company_names = Company.where(id: @overcommitted.map { |row| row[:company_id] }).pluck(:id, :name).to_h
      @overrides = SessionConcurrencyLimit.for_projects.order(:scope_id)
      @health = SessionAdmissionReconciler.snapshot

      render layout: "administrate/application"
    end
  end
end
