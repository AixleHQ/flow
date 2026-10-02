# frozen_string_literal: true

module Slack
  # Tells the Slack thread that started a workflow run that the run failed, and
  # what it failed with.
  #
  # A run launched from Slack is fire-and-forget for the person who typed the
  # mention: they get whatever the agent chose to post back, and nothing at all
  # when the run dies before the agent could post anything — which is exactly
  # when a failure most needs saying out loud. Whether a trigger wants this is
  # Chat::RunStatusReporter's call (TriggerBinding#status_reporting).
  #
  # Best-effort by construction: every path returns false rather than raising, so
  # a Slack outage can never turn a failed run into a failed state transition.
  class RunFailureNotifier
    class << self
      def call(run)
        return false if run.nil? || !run.failed?

        slack = run.shared_context.to_h["slack"].to_h
        channel = slack["channel"]
        return false if channel.blank?

        integration = integration_for(run, slack)
        return false if integration.nil?

        Slack::Notifier.post(
          integration: integration,
          channel: channel,
          thread_ts: slack["thread_ts"],
          text: message_for(run)
        ).present?
      rescue StandardError => e
        Rails.logger.error("[Slack::RunFailureNotifier] run ##{run&.id}: #{e.message}")
        false
      end

      private

      # Reply through the workspace that triggered the run, named in shared_context.
      def integration_for(run, slack)
        return nil if run.project.nil?

        Slack::InstallResolver.call(
          company_id: run.project.company_id, project_id: run.project_id,
          integration_id: slack["integration_id"], team_id: slack["team"]
        )
      end

      def message_for(run)
        summary = failure_summary(run)
        lines = [ ":x: *#{run.workflow&.name || 'Workflow'}* run ##{run.id} failed." ]
        lines << "> #{summary}" if summary.present?
        lines << run_url(run)
        lines.compact.join("\n")
      end

      # What actually went wrong: the quota case names itself, otherwise the last
      # failed step's message. Truncated — a container log dump in a Slack thread
      # helps nobody, and the run page has the whole thing.
      def failure_summary(run)
        if run.failure_reason == "quota_exceeded"
          return "#{run.failed_agent_credential&.agent_type || 'The connected account'} ran out of credits."
        end

        step = run.step_runs.where(state: "failed").order(:updated_at).last
        [ step&.step&.name, step&.error_message.to_s.truncate(400).presence ].compact.join(": ").presence ||
          run.failure_reason.to_s.humanize.presence
      end

      def run_url(run)
        return nil if run.project_id.blank?

        path = Rails.application.routes.url_helpers.company_project_workflow_run_path(run.project_id, run.id)
        "#{Settings.protocol}://#{Settings.domain}#{path}"
      end
    end
  end
end
