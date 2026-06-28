# frozen_string_literal: true

# One deployment-wide Slack Events API endpoint for the multi-workspace app.
# Every connected workspace POSTs here; we verify with the app-level signing
# secret, route by `team_id` to that workspace's install (WebhookEndpoint), and
# hand off to the same normalize → publish → dispatch pipeline the generic
# gateway uses. App-uninstall / token-revocation events deactivate the install.
class Webhooks::SlackController < ActionController::API
  LIFECYCLE_EVENTS = %w[app_uninstalled tokens_revoked].freeze

  def events
    raw = request.raw_post
    payload = safe_json(raw) || {}

    # Registration handshake — echo the challenge (sent before any install exists).
    return render(plain: payload["challenge"].to_s) if payload["type"] == "url_verification"

    return head :unauthorized unless verified?(raw)

    endpoint = endpoint_for(payload["team_id"].to_s)
    return head :ok if endpoint.nil? # unknown / disconnected workspace — ack and ignore

    inner_type = payload.dig("event", "type").to_s
    if LIFECYCLE_EVENTS.include?(inner_type)
      deactivate_install(endpoint)
      return head :ok
    end

    received = ReceivedWebhook.create!(
      webhook_endpoint: endpoint,
      idempotency_key: idempotency_key_for(endpoint, payload, raw),
      event_type: "slack",
      status: "received",
      raw_payload: payload
    )
    Webhooks::ProcessEventJob.perform_later(received.id)
    head :ok
  rescue ActiveRecord::RecordNotUnique
    head :ok # duplicate delivery (same event_id) — already accepted
  end

  private

  def verified?(raw)
    Webhooks::SignatureVerifier.verify(
      strategy: "slack_v0",
      secret: app_signing_secret,
      request: request,
      raw_body: raw
    ).ok?
  end

  def app_signing_secret
    Settings.slack.signing_secret
  end

  def endpoint_for(team_id)
    return nil if team_id.blank?

    WebhookEndpoint.active.find_by(slug: "slack-team-#{team_id}")
  end

  def deactivate_install(endpoint)
    endpoint.update(enabled: false)
    integration_id = endpoint.config.to_h["integration_id"]
    Integration.where(id: integration_id).update_all(status: "inactive") if integration_id
  end

  def idempotency_key_for(endpoint, payload, raw)
    payload["event_id"].presence || Digest::SHA256.hexdigest("#{endpoint.id}:#{raw}")
  end

  def safe_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError, TypeError
    nil
  end
end
