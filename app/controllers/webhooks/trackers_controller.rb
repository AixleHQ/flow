# frozen_string_literal: true

# Tracker webhook receiver for providers whose events do not arrive through an
# existing receiver (Azure and GitHub have their own): Jira, Linear and YouTrack. The provider
# authenticates the request and reduces it to Trackers::Notification — IDs and
# change hints only; the pipeline re-reads the issue itself.
class Webhooks::TrackersController < ActionController::API
  MAX_PAYLOAD_BYTES = 512 * 1024

  # Before anything reads `params`, which would parse an unbounded body first.
  before_action :enforce_payload_limit

  # A subscription's own endpoint: the token in the path routes, the provider
  # authenticates.
  def receive
    subscription = TrackerSubscription.live.find_by(endpoint_token: request.path_parameters[:endpoint_token])
    return head :not_found unless subscription

    raw = request.raw_post
    provider = Trackers::Provider.for(subscription.integration)
    return head :unauthorized unless provider.authentic_delivery?(request, raw, subscription)

    accept(subscription, provider, JSON.parse(raw), raw)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  # The one URL Atlassian allows Aixle's Jira app for every webhook it
  # registers; the payload names the webhooks it matched.
  def receive_app
    raw = request.raw_post
    return head :unauthorized unless Trackers::Jira::Webhooks.app_signed?(request)

    payload = JSON.parse(raw)
    Trackers::Jira::Webhooks.app_subscriptions(payload).each do |subscription|
      accept(subscription, Trackers::Provider.for(subscription.integration), payload, raw)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  # The one webhook of Aixle's Linear OAuth app, for every workspace that
  # installed it; the payload names the workspace.
  def receive_linear_app
    raw = request.raw_post
    return head :unauthorized unless Trackers::Linear::Webhooks.app_signed?(request, raw)

    payload = JSON.parse(raw)
    Trackers::Linear::Webhooks.app_subscriptions(payload).each do |subscription|
      accept(subscription, Trackers::Provider.for(subscription.integration), payload, raw)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def accept(subscription, provider, payload, raw)
    notifications = provider.parse_delivery(payload, subscription)
    subscription.update_columns(last_event_at: Time.current, status: "active", updated_at: Time.current)
    return if notifications.empty?

    dedup_key = provider.delivery_id(request, payload).presence || Digest::SHA256.hexdigest(raw)
    delivery = TrackerDelivery.record(subscription: subscription, dedup_key: dedup_key, notifications: notifications)
    Trackers::ProcessDeliveryJob.perform_later(delivery.id) if delivery
  end

  def enforce_payload_limit
    length = request.content_length
    head :content_too_large if length && length.to_i > MAX_PAYLOAD_BYTES
  end
end
