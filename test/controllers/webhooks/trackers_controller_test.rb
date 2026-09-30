# frozen_string_literal: true

require "test_helper"

class Webhooks::TrackersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    with_jira_oauth_app
    @integration = create(:integration, :jira, :active)
    @subscription = create(:tracker_subscription, integration: @integration, strategy: "manual", secret: "s3cret")
  end

  def issue_created(id: "10100")
    { webhookEvent: "jira:issue_created", timestamp: 1_727_690_400_000, user: { accountId: "557058:ada" },
      issue: { id: id, key: "ENG-1", self: "https://acme.atlassian.net/rest/api/2/issue/#{id}",
               fields: { project: { id: "10000", key: "ENG" } } } }
  end

  def signed_headers(raw, secret: "s3cret", delivery: "d-1")
    { "CONTENT_TYPE" => "application/json", "X-Atlassian-Webhook-Identifier" => delivery,
      "X-Hub-Signature" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw)}" }
  end

  test "a signed admin webhook is recorded once and processed out of the request" do
    raw = issue_created.to_json

    assert_enqueued_with(job: Trackers::ProcessDeliveryJob) do
      post "/webhooks/trackers/#{@subscription.endpoint_token}", params: raw, headers: signed_headers(raw)
    end
    post "/webhooks/trackers/#{@subscription.endpoint_token}", params: raw, headers: signed_headers(raw)

    assert_response :ok
    delivery = TrackerDelivery.sole
    assert_equal [ "d-1", "issue_created", "10100" ],
                 [ delivery.dedup_key, delivery.notifications.sole["kind"], delivery.notification_objects.sole.issue_id ]
    assert_equal "active", @subscription.reload.status
    assert_not_nil @subscription.last_event_at
  end

  test "a wrong signature, an unknown endpoint and a disabled subscription are refused" do
    raw = issue_created.to_json

    post "/webhooks/trackers/#{@subscription.endpoint_token}", params: raw, headers: signed_headers(raw, secret: "guess")
    assert_response :unauthorized
    post "/webhooks/trackers/nope", params: raw, headers: signed_headers(raw)
    assert_response :not_found
    @subscription.update!(status: "disabled")
    post "/webhooks/trackers/#{@subscription.endpoint_token}", params: raw, headers: signed_headers(raw)
    assert_response :not_found

    assert_equal 0, TrackerDelivery.count
  end

  test "an event about nothing a trigger can use is acknowledged and dropped" do
    raw = issue_created.merge(webhookEvent: "jira:issue_deleted").to_json

    post "/webhooks/trackers/#{@subscription.endpoint_token}", params: raw, headers: signed_headers(raw)

    assert_response :ok
    assert_equal 0, TrackerDelivery.count
  end

  test "an app webhook is routed by the webhook ids it matched" do
    oauth = create(:integration, :jira_oauth, :active)
    subscription = create(:tracker_subscription, integration: oauth, strategy: "api", provider_subscription_id: "4001")
    raw = issue_created.merge(matchedWebhookIds: [ 4001 ]).to_json
    token = JSON::JWT.new(exp: 5.minutes.from_now.to_i).sign("jira-app-secret", :HS256).to_s

    post "/webhooks/trackers/app/jira", params: raw, headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    assert_response :ok
    post "/webhooks/trackers/app/jira", params: raw, headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer forged" }
    assert_response :unauthorized

    assert_equal [ subscription.id ], TrackerDelivery.pluck(:tracker_subscription_id)
  end
end
