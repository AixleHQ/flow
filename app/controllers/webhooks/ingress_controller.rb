# frozen_string_literal: true

# Generic inbound webhook gateway. One endpoint for every registered source
# (Slack, custom apps, …) addressed by slug: POST /webhooks/in/:slug.
#
# Pipeline: resolve endpoint → (Slack URL-verification handshake) → verify
# signature on the raw body → dedup on a stable idempotency key → 2xx fast →
# hand off to Webhooks::ProcessEventJob (normalize → TriggerEngine.publish).
class Webhooks::IngressController < ActionController::API
  YOUTRACK_MAX_BODY = 512.kilobytes

  def receive
    # Access route parameters directly: `params` parses the JSON body before we
    # can enforce YouTrack's byte limit or reject malformed JSON.
    endpoint = WebhookEndpoint.active.find_by(slug: request.path_parameters[:slug])
    return head :not_found unless endpoint

    adapter = Webhooks::AdapterRegistry.for(endpoint.provider)
    if adapter
      return head :unsupported_media_type unless request.media_type == "application/json"
      raw = request.body.read(YOUTRACK_MAX_BODY + 1)
      return head :content_too_large if raw.bytesize > YOUTRACK_MAX_BODY
    else
      raw = request.raw_post
    end

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
      raw_body: raw,
      config: endpoint.config
    )
    return head :unauthorized unless verification.ok?

    payload = safe_json(raw)
    return head :bad_request unless payload.is_a?(Hash)
    if adapter
      integration = Integration.active.find_by(id: endpoint.config["integration_id"], provider: endpoint.provider)
      return head :ok unless integration
      event_type = adapter.classify(payload)
      return head :ok if event_type == :unsupported
      payload = adapter.redact(payload, event_type, integration)
      return head :ok if payload.nil?
      integration.update_column(:settings, integration.settings.merge("last_received_at" => Time.current.iso8601))
      return head :ok unless TriggerBinding.active.where(integration_id: integration.id, event_type: event_type).exists?
    end
    received = ReceivedWebhook.create!(
      webhook_endpoint: endpoint,
      idempotency_key: adapter ? adapter.dedup_key(endpoint, event_type, payload) : idempotency_key_for(endpoint, payload, raw),
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
