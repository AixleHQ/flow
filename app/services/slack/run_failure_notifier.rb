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
        summary = Chat::RunFailure.summary(run)
        lines = [ ":x: *#{run.workflow&.name || 'Workflow'}* run ##{run.id} failed." ]
        lines << "> #{summary}" if summary.present?
        lines << Chat::RunFailure.url(run)
        lines.compact.join("\n")
      end
    end
  end
end
