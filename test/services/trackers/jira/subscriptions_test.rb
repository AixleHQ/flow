# frozen_string_literal: true

require "test_helper"

class Trackers::Jira::SubscriptionsTest < ActiveSupport::TestCase
  setup do
    with_jira_oauth_app
    @jira = stub_jira!
  end

  test "a service-account connection gets one manual subscription with a secret for the admin webhook" do
    integration = create(:integration, :jira, :active)

    first = Trackers::Jira::Subscriptions.new(integration).ensure!
    again = Trackers::Jira::Subscriptions.new(integration).ensure!

    assert_equal [ first, "manual" ], [ again, first.strategy ]
    assert_equal 64, first.secret.length
    assert_equal first.secret, again.reload.secret
    assert_empty @jira.calls
  end

  test "a 3LO connection registers one webhook for its projects, to the app's single URL" do
    integration = create(:integration, :jira_oauth, :active)

    subscription = Trackers::Jira::Subscriptions.new(integration).ensure!

    call = @jira.calls_to(:register_webhook).sole
    assert_equal [ "https://flow.example.com/webhooks/trackers/app/jira", "project IN (10000, 10001)", Trackers::Jira::Webhooks::EVENTS ],
                 call.values_at(:url, :jql, :events)
    assert_equal [ "api", "active", @jira.webhook_registry.keys.sole ],
                 [ subscription.strategy, subscription.status, subscription.provider_subscription_id ]
    assert_in_delta 30.days.from_now, subscription.expires_at, 1.minute

    Trackers::Jira::Subscriptions.new(integration).ensure!
    assert_equal 1, @jira.calls_to(:register_webhook).size
  end

  test "changed projects replace the webhook, and ones no subscription holds any more are released" do
    integration = create(:integration, :jira_oauth, :active)
    subscription = Trackers::Jira::Subscriptions.new(integration).ensure!
    held_elsewhere = create(:tracker_subscription, integration: create(:integration, :jira_oauth, :active),
                                                   strategy: "api", provider_subscription_id: "555")
    @jira.webhook_registry["555"] = { id: "555" }
    @jira.webhook_registry["556"] = { id: "556" }
    integration.update!(settings: integration.settings.merge("jira_projects" => [ { "id" => "10000", "key" => "ENG" } ]))

    Trackers::Jira::Subscriptions.new(integration).ensure!

    assert_equal "project IN (10000)", subscription.reload.settings["jql"]
    assert_equal [ "555", subscription.provider_subscription_id ].sort, @jira.webhook_registry.keys.sort
    assert_equal "active", held_elsewhere.reload.status
  end

  test "a failed registration is recorded on the subscription" do
    integration = create(:integration, :jira_oauth, :active)
    @jira.fail_next(:register_webhook, Jira::Error.new("Only 5 webhooks per user", code: "validation_failed"))

    subscription = Trackers::Jira::Subscriptions.new(integration).ensure!

    assert_equal [ "failing", "Only 5 webhooks per user" ], [ subscription.status, subscription.last_error ]
  end

  test "refreshing extends the webhook, and registers a new one when Jira forgot it" do
    integration = create(:integration, :jira_oauth, :active)
    subscription = Trackers::Jira::Subscriptions.new(integration).ensure!
    subscription.update!(expires_at: 2.days.from_now)

    Trackers::Jira::Subscriptions.new(integration).refresh!(subscription)
    assert_in_delta 30.days.from_now, subscription.reload.expires_at, 1.minute

    @jira.webhook_registry.clear
    Trackers::Jira::Subscriptions.new(integration).refresh!(subscription)
    assert_equal 2, @jira.calls_to(:register_webhook).size
    assert_equal @jira.webhook_registry.keys.sole, subscription.reload.provider_subscription_id
  end

  test "nothing is registered while Atlassian cannot reach this deployment" do
    with_jira_oauth_app(webhook_base_url: "http://localhost:4000")

    assert_nil Trackers::Jira::Subscriptions.new(create(:integration, :jira_oauth, :active)).ensure!
    assert_not @jira.called?(:register_webhook)
  end
end
