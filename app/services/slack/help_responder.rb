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
        return false unless event.event_type.to_s.start_with?("slack.")

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
        company_id = event.company_id || event.project&.company_id
        return nil if company_id.blank?

        scope = Integration.active.where(provider: :slack, company_id: company_id)

        if (id = event.data.to_h["integration_id"]).present?
          by_id = scope.find_by(id: id)
          return by_id if by_id
        end

        scope.order(Arel.sql("project_id IS NULL")).first
      end

      def channel_bindings(event, channel)
        TriggerBinding.for_event(event)
          .includes(:workflow, :project)
          .select { |b| applies_to_channel?(b, channel) }
          .sort_by { |b| [ b.project&.name.to_s, catalog_label(b) ] }
      end

      def applies_to_channel?(binding, channel)
        pred = binding.filter_predicate.to_h
        return true unless pred.key?("channel")

        pred["channel"].to_s == channel.to_s
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
        workflow = binding.workflow&.name.presence || "workflow"
        pattern = text_pattern_for(binding)
        label = catalog_label(binding)
        project = binding.project&.name
        base = if label == workflow
          "• *#{escape_mrkdwn(workflow)}* (#{escape_mrkdwn(pattern)})"
        else
          "• *#{escape_mrkdwn(label)}* — #{escape_mrkdwn(workflow)} (#{escape_mrkdwn(pattern)})"
        end
        project.present? ? "#{base} _[#{escape_mrkdwn(project)}]_" : base
      end

      def catalog_label(binding)
        text_pattern_snippet(binding).presence || binding.workflow&.name.presence || "workflow"
      end

      def text_pattern_snippet(binding)
        text = binding.filter_predicate.to_h["text"]
        return nil if text.blank?

        if text.is_a?(Hash)
          text["value"].presence
        else
          text.to_s.presence
        end
      end

      def text_pattern_for(binding)
        text = binding.filter_predicate.to_h["text"]
        return "any message" if text.blank?

        if text.is_a?(Hash)
          value = text["value"]
          return "any message" if value.blank?

          op = text["op"].presence || "contains"
          "#{op} \"#{value}\""
        else
          "contains \"#{text}\""
        end
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
