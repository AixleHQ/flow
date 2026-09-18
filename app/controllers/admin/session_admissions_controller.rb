# frozen_string_literal: true

module Admin
  # The session queue's on switch, and the state an operator needs to decide
  # whether to touch it.
  #
  # WHY THIS EXISTS: a fresh installation turns admission on in the migration —
  # an empty database has nothing to drain. An installation with history cannot
  # do that, because enabling would put already-running sessions behind a queue
  # they were never admitted to, so it needs a deliberate act after the drain.
  # Until now that act was a rake task, which assumes shell access to a
  # production pod; a self-hosted operator has an admin login and nothing else.
  #
  # The buttons do not carry configuration. Activation applies the same drain
  # gate as the task and reads the same limits — company rows for what was sold,
  # project rows for how it was divided — so this page only decides when a
  # change of state is picked up.
  class SessionAdmissionsController < Admin::ApplicationController
    def show
      @policy = SessionAdmissionPolicy.current
      @scope_defaults = SessionAdmissionPolicy.scope_defaults
      @reserved_total = SessionConcurrencyLimit.for_projects.sum(:max_sessions)
      @company_limits = SessionConcurrencyLimit.for_companies.order(:scope_id)
      @overcommitted = SessionConcurrencyLimit.overcommitted_companies
      @company_names = Company.where(id: @overcommitted.map { |row| row[:company_id] }).pluck(:id, :name).to_h
      @overrides = SessionConcurrencyLimit.for_projects.order(:scope_id)
      @health = SessionAdmissionReconciler.snapshot

      render layout: "administrate/application"
    end

    def update
      case params[:commit_action]
      when "activate" then activate
      when "pause" then transition(paused: true, notice: "Admission paused. Queued requests are kept; occupied slots are untouched.")
      when "resume" then transition(paused: false, notice: "Admission resumed.", drain: true)
      else redirect_to admin_session_admission_path, alert: "Unknown action"
      end
    end

    private

    def activate
      policy = SessionAdmissionActivation.call
      redirect_to admin_session_admission_path, notice: activation_notice(policy)
    rescue ArgumentError, SessionAdmissionActivation::Refused => e
      # Both gates land here. Reporting them is the whole point: the operator is
      # being told what still has to finish before the queue can take over.
      redirect_to admin_session_admission_path, alert: e.message
    end

    def transition(paused:, notice:, drain: false)
      SessionAdmissionService.transaction do |policy|
        policy.update!(paused: paused, revision: policy.revision + 1)
      end
      granted = drain ? SessionAdmissionService.drain! : []
      redirect_to admin_session_admission_path,
        notice: drain ? "#{notice} Granted #{granted.size} queued request(s)." : notice
    end

    def activation_notice(policy)
      "Admission enabled: one queue per project, #{SessionAdmissionPolicy.scope_default('Project')} " \
        "concurrent sessions each unless the project sets its own. " \
        "A project is bounded by its company's limit, set on the company's own page."
    end
  end
end
