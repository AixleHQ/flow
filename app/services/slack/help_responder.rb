# frozen_string_literal: true

module Slack
  # Replies in-thread with the Slack ChatOps commands available for the channel
  # when a user @-mentions the bot with /help or with no matching trigger.
  #
  # Best-effort: every path returns false rather than raising, so a Slack outage
  # never turns a trigger dispatch into a failed outbox event.
  class HelpResponder
    class << self
      def call(event)
        return false if event.nil?
        return false unless Chat.event?(event)

        channel = event.data.to_h["channel"]
        return false if channel.blank?

        integration = integration_for(event)
        return false if integration.nil?

        bindings = channel_bindings(event, channel)
        text, blocks = format_catalog(bindings)

        Slack::Notifier.post(
          integration: integration,
          channel: channel,
          thread_ts: event.data["thread_ts"].presence || event.data["ts"],
          text: text,
          blocks: blocks
        ).present?
      rescue StandardError => e
        Rails.logger.error("[Slack::HelpResponder] event ##{event&.id}: #{e.message}")
        false
      end

      private

      def integration_for(event)
        Slack::InstallResolver.call(
          company_id: event.company_id || event.project&.company_id, project_id: event.project_id,
          integration_id: event.data.to_h["integration_id"], team_id: event.data.to_h["team"]
        )
      end

      def channel_bindings(event, channel)
        Chat::HelpCatalog.bindings(event, channel)
      end

      def format_catalog(bindings)
        if bindings.empty?
          text = "No Slack triggers configured for this channel."
          return [ text, [ section_block(text) ] ]
        end

        lines = bindings.map { |b| catalog_line(b) }
        text = "Available commands:\n#{lines.join("\n")}"
        blocks = [
          section_block("*Available commands*"),
          section_block(lines.join("\n"))
        ]
        [ text, blocks ]
      end

      def catalog_line(binding)
        workflow = Chat::HelpCatalog.workflow_name(binding)
        pattern = Chat::HelpCatalog.pattern(binding)
        label = Chat::HelpCatalog.label(binding)
        project = binding.project&.name
        base = if label == workflow
          "• *#{escape_mrkdwn(workflow)}* (#{escape_mrkdwn(pattern)})"
        else
          "• *#{escape_mrkdwn(label)}* — #{escape_mrkdwn(workflow)} (#{escape_mrkdwn(pattern)})"
        end
        project.present? ? "#{base} _[#{escape_mrkdwn(project)}]_" : base
      end

      def section_block(mrkdwn)
        { "type" => "section", "text" => { "type" => "mrkdwn", "text" => mrkdwn } }
      end

      # Slack mrkdwn treats &, <, > specially inside *bold* / _italic_.
      def escape_mrkdwn(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
