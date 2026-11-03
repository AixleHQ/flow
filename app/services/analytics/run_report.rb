# frozen_string_literal: true

module Analytics
  # What a workflow run reports when it starts and when it ends. A run is
  # charged to whoever started it, or, for one a trigger started, to whoever
  # made the trigger; a run neither can answer for reports nothing.
  class RunReport
    FINAL_STATES = %w[completed failed cancelled].freeze
    STATUSES = { "completed" => "succeeded", "failed" => "failed", "cancelled" => "cancelled" }.freeze

    def initialize(run)
      @run = run
    end

    def started
      return unless Analytics.enabled?

      capture("workflow_run_started", trigger: trigger, is_first: first_run?)
    end

    def finished
      return unless Analytics.enabled?

      status = STATUSES.fetch(run.state.to_s)
      duration = run.completed_at && run.created_at && (run.completed_at - run.created_at).round
      capture("workflow_run_finished", status: status, duration_sec: duration, is_first: first_finished?)
      return unless status == "failed"

      capture("workflow_run_failed", failed_step_index: failed_step_index, reason: failure_reason)
    end

    private

    attr_reader :run

    def capture(event, props)
      user = attributed_user
      return if user.nil?

      Analytics.capture(event, user: user, company: project.company, project: project, props: props, via: via)
    end

    def project = @project ||= run.project

    def attributed_user
      run.user || binding&.created_by
    end

    def binding
      return @binding if defined?(@binding)

      @binding = (TriggerDispatch.find_by(workflow_run_id: run.id)&.trigger_binding if run.source.to_s == "trigger")
    end

    def via
      case run.source.to_s
      when "mcp" then "mcp"
      when "trigger" then "system"
      else "ui"
      end
    end

    def trigger
      case run.source.to_s
      when "mcp" then "mcp"
      when "retry" then "retry"
      when "trigger" then trigger_kind
      else run.board_task_id ? "board" : "manual"
      end
    end

    def trigger_kind
      # A card dropped on a column with a workflow bound to it has no trigger.
      return run.board_task_id ? "board" : "custom_event" if binding.nil?
      return "schedule" if binding.schedule?
      return "webhook" if binding.webhook?
      return binding.chat_provider || "chat" if binding.chat?
      return "tracker" if binding.tracker_event?

      "custom_event"
    end

    def company_runs = WorkflowRun.joins(:project).where(projects: { company_id: project.company_id })

    def first_run? = !company_runs.where.not(id: run.id).exists?

    def first_finished?
      !company_runs.where(state: FINAL_STATES).where.not(id: run.id).exists?
    end

    def failed_step_run
      @failed_step_run ||= StepRun.where(workflow_run_id: run.id, state: "failed").order(:created_at).first
    end

    def failed_step_index
      failed_step_run&.step&.position
    end

    def failure_reason
      case failed_step_run&.error_category.to_s
      when "quota_exceeded" then return "provider_quota"
      when "auth_expired" then return "auth_expired"
      end

      text = [ run.failure_reason, failed_step_run&.error_message ].compact.join(" ").downcase
      return "timeout" if text.match?(/timed? ?out|stale/)
      return "config_missing" if text.match?(/config|credential|not configured|missing/)

      "agent_error"
    end
  end
end
