# frozen_string_literal: true

module Teams
  # Tells someone addressing the bot from an organization no Aixle company has
  # connected why nothing happens (docs/design/teams-integration.md §6.2). Once a
  # day per conversation, and nothing of the message is kept: the job carries
  # only where to answer, taken from the authenticated activity.
  class UnboundTenantHintJob < ApplicationJob
    queue_as :default

    THROTTLE = 1.day

    def self.hint_once(activity)
      conversation_id = activity.dig("conversation", "id").to_s.split(";messageid=", 2).first
      return if conversation_id.blank?
      return unless Rails.cache.write("teams:unbound-hint:#{conversation_id}", true, unless_exist: true, expires_in: THROTTLE)

      perform_later(
        "service_url" => activity["serviceUrl"], "conversation_id" => activity.dig("conversation", "id"),
        "activity_id" => activity["id"], "tenant_id" => activity.dig("conversation", "tenantId"),
        "bot" => { "id" => activity.dig("recipient", "id") }
      )
    end

    def perform(reference)
      Teams::ConnectorClient.reply(reference, type: "message", textFormat: "markdown", text: text)
    rescue Teams::Error => e
      Rails.logger.warn("[Teams::UnboundTenantHintJob] #{e.message}")
    end

    def text
      "This Microsoft 365 organization hasn't connected Aixle Flow yet, so I can't start anything here. " \
        "An Aixle admin can connect it under Integrations → Microsoft Teams: #{Settings.protocol}://#{Settings.domain}/"
    end
  end
end
