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
      raw_body: raw,
      config: endpoint.config
    )
    return head :unauthorized unless verification.ok?

    payload = safe_json(raw)
    return head :bad_request unless payload.is_a?(Hash)
    payload = normalize_youtrack_ingress(endpoint, payload) if endpoint.youtrack?
    return head :ok if payload.nil?
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

  YOUTRACK_TEXT_LIMIT = 500

  def normalize_youtrack_ingress(endpoint, payload)
    integration = Integration.active.find_by(id: endpoint.config["integration_id"], provider: "youtrack")
    return nil unless integration
    event = payload["event"].to_s
    issue = payload["issue"].to_h
    project = issue["project"].to_h
    return nil unless %w[issueCreated commentAdded].include?(event)
    return nil unless project["id"].to_s == integration.youtrack_project_id

    base = { "event" => event, "timestamp" => payload["timestamp"], "issue" => {
      "id" => issue["id"], "idReadable" => issue["idReadable"], "summary" => bounded(issue["summary"]),
      "description" => bounded(issue["description"]), "project" => project.slice("id", "name", "shortName"),
      "reporter" => issue["reporter"].to_h.slice("id", "login")
    } }
    if event == "commentAdded"
      comment = payload["comment"].to_h
      login = integration.settings["bot_login"].to_s
      text = comment["text"].to_s
      return nil if login.blank? || !text.match?(/(?<![\w.-])@#{Regexp.escape(login)}(?![\w.-])/i)
      return nil if comment.dig("author", "id").to_s == integration.settings["bot_user_id"].to_s
      base["comment"] = comment.slice("id").merge("text" => bounded(text), "author" => comment["author"].to_h.slice("id", "login"))
    end
    binding_scope = TriggerBinding.active.where(integration_id: integration.id,
      event_type: event == "issueCreated" ? "youtrack.issue.created" : "youtrack.comment.mentioned")
    return nil unless binding_scope.exists?
    integration.update_column(:settings, integration.settings.merge("last_received_at" => Time.current.iso8601))
    base
  end

  def bounded(value)
    value.to_s.truncate(YOUTRACK_TEXT_LIMIT, omission: "… [truncated]")
  end

  def idempotency_key_for(endpoint, payload, raw)
    explicit =
      case endpoint.provider.to_s
      when "slack" then payload["event_id"]
      when "youtrack"
        kind = payload["event"]
        source_id = kind == "commentAdded" ? payload.dig("comment", "id") : payload.dig("issue", "id")
        Digest::SHA256.hexdigest([endpoint.id, kind, source_id].join(":")) if source_id.present?
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
