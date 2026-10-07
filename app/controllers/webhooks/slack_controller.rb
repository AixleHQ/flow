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

  # Interactivity: the "Run workflow" shortcut and its modal's submission
  # (docs/design/teams-integration.md §21). Slack waits three seconds.
  def interactions
    return head :unauthorized unless verified?(request.raw_post)

    payload = safe_json(params[:payload].to_s) || {}
    integration = integration_for(payload.dig("team", "id").to_s)
    return head :ok if integration.nil?

    case payload["type"]
    when "message_action"
      Slack::RunAction.shortcut(integration, payload) if payload["callback_id"] == Slack::RunAction::CALLBACK
      head :ok
    when "view_submission"
      return head :ok unless payload.dig("view", "callback_id") == Slack::RunAction::CALLBACK

      render json: Slack::RunAction.submit(integration, payload)
    else
      head :ok # a link button's click, which opens the browser by itself
    end
  end

  # The app's slash command: `run` and `status`.
  def commands
    return head :unauthorized unless verified?(request.raw_post)

    integration = integration_for(params[:team_id].to_s)
    if integration.nil?
      return render(json: { response_type: "ephemeral", text: "This Slack workspace is not connected to Aixle." })
    end

    answer = Slack::RunAction.command(integration,
                                      params.permit(:command, :text, :team_id, :user_id, :channel_id, :trigger_id).to_h)
    answer ? render(json: answer) : head(:ok)
  end

  private

  def integration_for(team_id)
    endpoint = endpoint_for(team_id)
    Integration.active.find_by(id: endpoint&.config.to_h["integration_id"], provider: :slack)
  end

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
