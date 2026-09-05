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
  # The buttons do not carry configuration. Activation reads the same
  # SESSION_CONCURRENCY_LIMIT the deployment sets and applies the same drain
  # gate as the task — the environment stays the source of truth for capacity,
  # and this only decides when it is picked up.
  class SessionAdmissionsController < Admin::ApplicationController
    def show
      @policy = SessionAdmissionPolicy.current
      @scope_defaults = SessionAdmissionPolicy.scope_defaults
      @configured_limit = ENV["SESSION_CONCURRENCY_LIMIT"].to_s.strip.presence
      @overrides = SessionConcurrencyLimit.order(:scope_type, :scope_id)
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
      policy = SessionAdmissionPolicy.sync!
      redirect_to admin_session_admission_path, notice: activation_notice(policy)
    rescue ArgumentError => e
      # The drain gate. Reporting it is the whole point: the operator is being
      # told what still has to finish before the queue can take over.
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
      return "Admission enabled: one installation-wide queue of #{policy.installation_limit} concurrent sessions." if policy.installation_limit

      defaults = SessionAdmissionPolicy.scope_defaults
      "Admission enabled with per-scope queues: #{defaults['Project']} per project, " \
        "#{defaults['User']} per user for project-less sessions."
    end
  end
end
