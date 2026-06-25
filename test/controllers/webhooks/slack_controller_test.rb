# frozen_string_literal: true

require "test_helper"

class Webhooks::SlackControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "app-signing-secret"

  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
    @integration = Integration.create!(
      provider: :slack, company: @company, project: @project, connected_by: @user,
      name: "Acme", status: :active, settings: { "team_id" => "T1" }
    )
    @endpoint = create(:webhook_endpoint,
      slug: "slack-team-T1", provider: :slack, verification_strategy: :slack_v0,
      project: @project, company: @company, config: { "integration_id" => @integration.id, "team_id" => "T1" })

    # App-level signing secret (operator-set; unset in the test env).
    Webhooks::SlackController.any_instance.stubs(:app_signing_secret).returns(SECRET)
  end

  def slack_headers(raw, ts: Time.current.to_i.to_s, secret: SECRET)
    sig = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{ts}:#{raw}")}"
    { "X-Slack-Request-Timestamp" => ts, "X-Slack-Signature" => sig, "CONTENT_TYPE" => "application/json" }
  end

  test "responds to the url_verification challenge" do
    raw = { type: "url_verification", challenge: "abc123" }.to_json
    post "/webhooks/slack/events", params: raw, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :ok
    assert_equal "abc123", response.body
  end

  test "rejects an invalid signature" do
    raw = { type: "event_callback", team_id: "T1", event: { type: "message", channel: "C1" } }.to_json
    headers = slack_headers(raw).merge("X-Slack-Signature" => "v0=deadbeef")

    post "/webhooks/slack/events", params: raw, headers: headers

    assert_response :unauthorized
    assert_equal 0, ReceivedWebhook.count
  end

  test "routes a valid signed event by team_id to the install and enqueues processing" do
    raw = {
      type: "event_callback", event_id: "Ev1", team_id: "T1",
      event: { type: "message", channel: "C1", user: "U1", text: "hi" }
    }.to_json

    assert_difference -> { ReceivedWebhook.where(webhook_endpoint_id: @endpoint.id).count }, 1 do
      assert_enqueued_with(job: Webhooks::ProcessEventJob) do
        post "/webhooks/slack/events", params: raw, headers: slack_headers(raw)
      end
    end
    assert_response :ok
  end

  test "acks and ignores events from an unknown workspace" do
    raw = { type: "event_callback", event_id: "Ev2", team_id: "T-unknown",
            event: { type: "message", channel: "C1" } }.to_json

    assert_no_difference -> { ReceivedWebhook.count } do
      post "/webhooks/slack/events", params: raw, headers: slack_headers(raw)
    end
    assert_response :ok
  end

  test "is idempotent on redelivery of the same event_id" do
    raw = { type: "event_callback", event_id: "Ev-dup", team_id: "T1",
            event: { type: "message", channel: "C1" } }.to_json

    post "/webhooks/slack/events", params: raw, headers: slack_headers(raw)
    post "/webhooks/slack/events", params: raw, headers: slack_headers(raw)

    assert_response :ok
    assert_equal 1, ReceivedWebhook.where(idempotency_key: "Ev-dup").count
  end

  test "app_uninstalled deactivates the install and does not enqueue work" do
    raw = { type: "event_callback", team_id: "T1", event: { type: "app_uninstalled" } }.to_json

    assert_no_enqueued_jobs do
      post "/webhooks/slack/events", params: raw, headers: slack_headers(raw)
    end

    assert_response :ok
    assert_not @endpoint.reload.enabled
    assert @integration.reload.inactive?
  end
end
