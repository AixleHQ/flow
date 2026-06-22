# frozen_string_literal: true

# Generic inbound webhook gateway. One endpoint for every registered source
# (Slack, custom apps, …) addressed by slug: POST /webhooks/in/:slug.
#
# Pipeline: resolve endpoint → (Slack URL-verification handshake) → verify
# signature on the raw body → dedup on a stable idempotency key → 2xx fast →
# hand off to Webhooks::ProcessEventJob (normalize → TriggerEngine.publish).
class Webhooks::IngressController < ActionController::API
  def receive
    endpoint = WebhookEndpoint.active.find_by(slug: params[:slug])
    return head :not_found unless endpoint

    raw = request.raw_post

    # Slack registration handshake — echo the challenge back.
    if endpoint.slack?
      parsed = safe_json(raw)
      if parsed.is_a?(Hash) && parsed["type"] == "url_verification"
        return render plain: parsed["challenge"].to_s
      end
    end

    verification = Webhooks::SignatureVerifier.verify(
      strategy: endpoint.verification_strategy,
      secret: endpoint.secret,
      request: request,
      raw_body: raw
    )
    return head :unauthorized unless verification.ok?

    payload = safe_json(raw) || {}
    received = ReceivedWebhook.create!(
      webhook_endpoint: endpoint,
      idempotency_key: idempotency_key_for(endpoint, payload, raw),
      event_type: endpoint.provider,
      status: "received",
      raw_payload: payload
    )

    Webhooks::ProcessEventJob.perform_later(received.id)
    head :ok
  rescue ActiveRecord::RecordNotUnique
    # Duplicate delivery (same idempotency key) — already accepted & processing.
    head :ok
  end

  private

  def idempotency_key_for(endpoint, payload, raw)
    explicit =
      case endpoint.provider.to_s
      when "slack" then payload["event_id"]
      else request.headers["X-Idempotency-Key"] || request.headers["X-GitHub-Delivery"]
      end

    explicit.presence || Digest::SHA256.hexdigest("#{endpoint.id}:#{raw}")
  end

  def safe_json(raw)
    JSON.parse(raw)
  rescue JSON::ParserError, TypeError
    nil
  end
end
