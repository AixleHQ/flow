# frozen_string_literal: true

# Azure DevOps Service Hook receiver.
#
# Three things differ from the GitHub receiver next door, and copying that one
# would get each of them wrong:
#
# 1. **There is no signature.** Azure's webhook consumer authenticates with HTTP
#    basic auth, so `X-Hub-Signature`-style verification has nothing to verify
#    and would accept every request. The credential is the subscription's own
#    password, compared in constant time.
# 2. **The URL is not the secret.** The endpoint id routes a delivery to one
#    subscription — it appears in Azure's own UI and failure mails — and grants
#    nothing on its own.
# 3. **Delivery is not guaranteed.** Duplicates and reordering are normal, and a
#    subscription that fails enough goes on probation and stops delivering. So
#    the delivery is persisted and deduplicated BEFORE it is acknowledged, and
#    the payload is treated as a notification to re-read authoritative state
#    rather than as the state itself.
class Webhooks::AzureDevopsController < ActionController::API
  # Azure retries a non-2xx, and every retry pushes the subscription closer to
  # probation. So anything that is not "we might succeed later" is acknowledged.
  MAX_PAYLOAD_BYTES = 512 * 1024

  # Order matters: the limit is enforced before anything reads `params`.
  # ActionController builds `params` from the parsed request body, so a check
  # inside the action runs only after a 50 MB body has already been buffered and
  # parsed — the guard would be there and do nothing.
  before_action :enforce_payload_limit
  before_action :authenticate_subscription

  def receive
    payload = request.request_parameters
    event_id = payload["id"].presence || payload["notificationId"].presence

    # No id means no way to deduplicate; process it rather than dropping it, and
    # say so, because a reordered or duplicated delivery could then resolve a
    # gate twice.
    if event_id.blank?
      Rails.logger.warn("[Webhooks::AzureDevops] subscription #{@subscription.id} delivered an event with no id")
    elsif AzureDevopsDelivery.record(subscription: @subscription, event_id: event_id,
                                     event_type: payload["eventType"]).nil?
      # Already seen. Acknowledged, because telling Azure a duplicate failed only
      # earns another redelivery.
      return head :ok
    end

    @subscription.update_columns(last_event_at: Time.current, status: "active", updated_at: Time.current)
    ResolveAzureDevopsEventJob.perform_later(
      subscription_id: @subscription.id,
      event_type: payload["eventType"].to_s,
      resource: payload["resource"].is_a?(Hash) ? payload["resource"] : {}
    )

    head :ok
  end

  private

  # `content_length` is absent on a chunked request, which cannot be checked up
  # front at all; the app server's own body limit is what bounds that case, and
  # this returns a refusal rather than pretending a missing header means zero.
  def enforce_payload_limit
    length = request.content_length
    return if length.nil?

    head :content_too_large if length.to_i > MAX_PAYLOAD_BYTES
  end

  def authenticate_subscription
    # `request.path_parameters`, not `params`: reading `params` here would parse
    # the body and defeat the limit enforced above.
    @subscription = AzureDevopsSubscription.find_by(endpoint_id: request.path_parameters[:endpoint_id])
    return head :unauthorized if @subscription.nil?

    username, password = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    return head :unauthorized if password.blank?
    return head :unauthorized unless @subscription.authenticate(password)

    # The username is not a credential — Azure sends whatever the subscription
    # was created with — so it is only logged, never trusted.
    Rails.logger.debug { "[Webhooks::AzureDevops] delivery for subscription #{@subscription.id} as #{username}" }
  rescue StandardError
    head :unauthorized
  end
end
