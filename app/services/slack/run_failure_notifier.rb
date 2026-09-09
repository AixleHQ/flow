# frozen_string_literal: true

module Slack
  # Tells the Slack thread that started a workflow that it failed, and what it
  # failed with.
  #
  # Two ways a Slack-triggered workflow can fail silently:
  #
  #   * the run reaches `failed` state (step/session error, output validation,
  #     quota, stale-run reaper, Temporal activity failure) — #call, off the AASM
  #     `fail` transition;
  #   * the launch is skipped before a run is ever persisted (e.g. `validate_mode!`
  #     rejects an interactive step) — #notify_launch_skip, off TriggerEngine's
  #     dispatch ledger.
  #
  # Either way the person who typed the mention gets nothing, which is exactly
  # when a failure most needs saying out loud. Opt-out per trigger
  # (TriggerBinding#notify_on_failure).
  #
  # Best-effort by construction: every path returns false rather than raising, so
  # a Slack outage can never turn a failed run into a failed state transition or
  # break dispatch. Idempotent: the claim on TriggerDispatch#slack_failure_notified_at
  # means job retries never post the same failure twice.
  class RunFailureNotifier
    # Reason strings are pulled from raw error text; scrub anything that smells
    # like a credential before it lands in a channel.
    SECRET_PATTERNS = [
      /xox[abprs]-[A-Za-z0-9-]+/,
      /\bBearer\s+[A-Za-z0-9._\-]+/i,
      /\bAKIA[0-9A-Z]{16}\b/,
      /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/,
      /\b(?:api[_-]?key|token|secret|password|passwd|pwd)\s*[=:]\s*\S+/i,
      /\b[A-Fa-f0-9]{32,}\b/
    ].freeze

    REASON_LIMIT = 300

    class << self
      def call(run)
        return false if run.nil? || !run.failed?

        slack = run.shared_context.to_h["slack"].to_h
        channel = slack["channel"]
        return false if channel.blank?

        dispatch = TriggerDispatch.where(workflow_run_id: run.id).order(:id).last
        return false unless notify?(dispatch)

        integration = integration_for(run.project, slack["integration_id"])
        return false if integration.nil?

        return false unless claim(dispatch)

        post_or_release(dispatch) do
          Slack::Notifier.post(
            integration: integration,
            channel: channel,
            thread_ts: slack["thread_ts"],
            text: message_for(run)
          )
        end
      rescue StandardError => e
        Rails.logger.error("[Slack::RunFailureNotifier] run ##{run&.id}: #{e.message}")
        false
      end

      # A launch that was accepted (the mention matched a workflow) but skipped
      # before a run existed. Reply using the event's own coordinates — there is
      # no run and no shared_context to read.
      def notify_launch_skip(dispatch)
        return false if dispatch.nil? || dispatch.status != "skipped"
        return false unless notify?(dispatch)

        event = dispatch.trigger_event
        return false unless event&.event_type.to_s.start_with?("slack.")

        channel = event.data["channel"]
        return false if channel.blank?

        integration = integration_for(dispatch.trigger_binding.project, event.data["integration_id"])
        return false if integration.nil?

        return false unless claim(dispatch)

        post_or_release(dispatch) do
          Slack::Notifier.post(
            integration: integration,
            channel: channel,
            thread_ts: event.data["thread_ts"] || event.data["ts"],
            text: launch_skip_message(dispatch)
          )
        end
      rescue StandardError => e
        Rails.logger.error("[Slack::RunFailureNotifier] dispatch ##{dispatch&.id}: #{e.message}")
        false
      end

      private

      # The binding that started this launch has to exist and still want the
      # notification. A run with Slack context but no binding (a re-run started by
      # hand from a Slack-born run, which inherits shared_context) is left alone:
      # nobody asked for a notification on it.
      def notify?(dispatch)
        dispatch&.trigger_binding&.notify_on_failure?
      end

      # Atomic claim: the UPDATE only touches the row while the column is still
      # NULL, so exactly one caller ever gets through — job retries, a duplicate
      # enqueue, and the reaper + WorkflowService.fail both landing on the same
      # run all collapse to a single reply. Claimed just before the post and
      # released again (see #post_or_release) if the post never lands, so a Slack
      # outage or a config gap leaves the notice retryable rather than eaten.
      def claim(dispatch)
        TriggerDispatch.where(id: dispatch.id, slack_failure_notified_at: nil)
                       .update_all(slack_failure_notified_at: Time.current) == 1
      end

      # Hold the claim only for a post that actually lands. Slack::Notifier.post
      # swallows a Slack outage and returns false rather than raising, so a falsy
      # result has to release the claim too — otherwise a transient failure eats
      # the notice for good.
      def post_or_release(dispatch)
        posted = yield
        release(dispatch) unless posted
        posted
      rescue StandardError
        release(dispatch)
        raise
      end

      def release(dispatch)
        TriggerDispatch.where(id: dispatch.id).update_all(slack_failure_notified_at: nil)
      end

      # Reply through the SAME workspace that triggered the launch — its install is
      # named in the Slack context / event — so a company with several connected
      # workspaces answers in the right one. Mirrors InternalTools::SlackPostMessage
      # #slack_integration, including its project-first fallback.
      def integration_for(project, integration_id)
        return nil if project.nil?

        scope = Integration.active.where(provider: :slack, company_id: project.company_id)

        if integration_id.present?
          by_id = scope.find_by(id: integration_id)
          return by_id if by_id
        end

        scope.where("project_id = :pid OR project_id IS NULL", pid: project.id)
             .order(Arel.sql("project_id IS NULL"))
             .first
      end

      def message_for(run)
        summary = failure_summary(run)
        lines = [ ":x: *#{run.workflow&.name || 'Workflow'}* run ##{run.id} failed." ]
        lines << "> #{summary}" if summary.present?
        lines << run_url(run)
        lines.compact.join("\n")
      end

      def launch_skip_message(dispatch)
        name = dispatch.trigger_binding.workflow&.name || "Workflow"
        reason = redact(dispatch.detail.to_h["reason"]).truncate(REASON_LIMIT).presence || "Workflow failed."
        ":x: *#{name}* failed to start.\n> #{reason}"
      end

      # What actually went wrong: the known failure_reason values name themselves,
      # otherwise the last failed step's message. Truncated and scrubbed — a
      # container log dump in a Slack thread helps nobody, and the run page has
      # the whole thing.
      def failure_summary(run)
        case run.failure_reason
        when "quota_exceeded"
          return "#{run.failed_agent_credential&.agent_type || 'The connected account'} ran out of credits."
        when "stale_run"
          return "The run timed out and was cleaned up as stale."
        end

        step = run.step_runs.where(state: "failed").order(:updated_at).last
        [ step&.step&.name, redact(step&.error_message).truncate(REASON_LIMIT).presence ].compact.join(": ").presence ||
          run.failure_reason.to_s.humanize.presence
      end

      def redact(text)
        SECRET_PATTERNS.reduce(text.to_s) { |acc, re| acc.gsub(re, "[redacted]") }
      end

      def run_url(run)
        return nil if run.project_id.blank?

        "https://#{Settings.domain}/company/projects/#{run.project_id}/workflow_runs/#{run.id}"
      end
    end
  end
end
