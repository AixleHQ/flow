# frozen_string_literal: true

require "test_helper"

class Webhooks::IngressControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "slack-signing-secret"

  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.company)
    @endpoint = create(:webhook_endpoint,
      slug: "slack-test", provider: :slack, verification_strategy: :slack_v0,
      secret: SECRET, project: @project)
  end

  def slack_headers(raw, ts: Time.current.to_i.to_s, secret: SECRET)
    sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{ts}:#{raw}")}"
    { "X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => sig, "CONTENT_TYPE" => "application/json" }
  end

  test "unknown slug returns 404" do
    post "/webhooks/in/does-not-exist", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end

  test "responds to the Slack url_verification challenge" do
    raw = { type: "url_verification", challenge: "abc123" }.to_json
    post "/webhooks/in/slack-test", params: raw, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :ok
    assert_equal "abc123", response.body
  end

  test "rejects an invalid signature" do
    raw = { type: "event_callback", event_id: "Ev1", event: { type: "message", channel: "C1" } }.to_json
    headers = slack_headers(raw).merge("X-Slack-Signature" => "v0=deadbeef")

    post "/webhooks/in/slack-test", params: raw, headers: headers

    assert_response :unauthorized
    assert_equal 0, ReceivedWebhook.count
  end

  test "accepts a valid signed event, stores it and enqueues processing" do
    raw = {
      type: "event_callback", event_id: "Ev1", team_id: "T1",
      event: { type: "message", channel: "C1", user: "U1", text: "hi" }
    }.to_json

    assert_difference -> { ReceivedWebhook.count }, 1 do
      assert_enqueued_with(job: Webhooks::ProcessEventJob) do
        post "/webhooks/in/slack-test", params: raw, headers: slack_headers(raw)
      end
    end

    assert_response :ok
  end

  test "is idempotent on redelivery of the same Slack event_id" do
    raw = { type: "event_callback", event_id: "Ev-dup", event: { type: "message", channel: "C1" } }.to_json

    post "/webhooks/in/slack-test", params: raw, headers: slack_headers(raw)
    post "/webhooks/in/slack-test", params: raw, headers: slack_headers(raw)

    assert_response :ok
    assert_equal 1, ReceivedWebhook.where(idempotency_key: "Ev-dup").count
  end
end
