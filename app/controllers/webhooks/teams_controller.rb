# frozen_string_literal: true

# The Azure Bot's messaging endpoint: every Teams activity for the deployment's
# bot, from every tenant (docs/design/teams-integration.md §7). Authenticate,
# keep only what was addressed to the bot, and hand it to the same
# normalize → publish → dispatch pipeline Slack uses.
class Webhooks::TeamsController < ActionController::API
  def activities
    activity = safe_json(request.raw_post)
    return head :bad_request unless activity.is_a?(Hash)

    begin
      Teams::ActivityAuthenticator.authenticate!(request.authorization, activity)
    rescue Teams::ActivityAuthenticator::Unauthorized => e
      Rails.logger.warn("[Webhooks::TeamsController] rejected activity: #{e.message}")
      return head :unauthorized
    end

    # A tenant no company has connected is acknowledged and otherwise ignored.
    endpoint = endpoint_for(activity.dig("channelData", "tenant", "id") || activity.dig("conversation", "tenantId"))
    return head :ok if endpoint.nil? || !addressed?(activity)

    received = ReceivedWebhook.create!(
      webhook_endpoint: endpoint,
      idempotency_key: "#{activity.dig('conversation', 'id')}:#{activity['id']}",
      event_type: "teams",
      status: "received",
      raw_payload: without_download_urls(activity)
    )
    Webhooks::ProcessEventJob.perform_later(received.id)
    head :ok
  rescue ActiveRecord::RecordNotUnique
    head :ok # the Connector redelivers on timeout
  end

  private

  # With resource-specific consent Teams delivers every channel message, not only
  # the ones that mention the bot. Those are dropped here, before anything is
  # stored. A mention counts only as an entity naming this bot — typed "@name"
  # text is not one.
  def addressed?(activity)
    return false unless activity["type"] == "message"
    return false if activity.dig("from", "id").to_s.start_with?("28:")
    return true if activity.dig("conversation", "conversationType") == "personal"

    Array(activity["entities"]).any? do |entity|
      entity["type"] == "mention" && entity.dig("mentioned", "id") == activity.dig("recipient", "id")
    end
  end

  def endpoint_for(tenant_id)
    return nil unless tenant_id.to_s.match?(Teams::Config::GUID)

    WebhookEndpoint.active.find_by(slug: "teams-tenant-#{tenant_id}")
  end

  # A 1:1 attachment's downloadUrl works without a token, so it is a credential
  # for as long as it lives; nothing reads it until file ingestion exists.
  def without_download_urls(activity)
    attachments = Array(activity["attachments"]).map do |attachment|
      next attachment unless attachment.is_a?(Hash) && attachment["content"].is_a?(Hash)

      attachment.merge("content" => attachment["content"].except("downloadUrl"))
    end
    activity.merge("attachments" => attachments)
  end

  def safe_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError, TypeError
    nil
  end
end
