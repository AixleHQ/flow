# frozen_string_literal: true

require "test_helper"

class Trackers::Jira::WebhooksTest < ActiveSupport::TestCase
  setup { with_jira_oauth_app }

  def request_with(headers)
    ActionDispatch::Request.new(Rack::MockRequest.env_for("/", headers.transform_keys { |k| "HTTP_#{k.upcase.tr('-', '_')}" }))
  end

  def jwt(claims, secret: "jira-app-secret", alg: :HS256)
    JSON::JWT.new(claims).sign(secret, alg).to_s
  end

  test "an admin webhook is authentic when it signs its body with the subscription's secret" do
    body = '{"webhookEvent":"jira:issue_created"}'
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 's3cret', body)}"

    assert Trackers::Jira::Webhooks.signed?(request_with("X-Hub-Signature" => signature), body, "s3cret")
    assert_not Trackers::Jira::Webhooks.signed?(request_with("X-Hub-Signature" => signature), "#{body} ", "s3cret")
    assert_not Trackers::Jira::Webhooks.signed?(request_with("X-Hub-Signature" => signature), body, "other")
    assert_not Trackers::Jira::Webhooks.signed?(request_with("X-Hub-Signature" => signature.sub("sha256", "sha1")), body, "s3cret")
    assert_not Trackers::Jira::Webhooks.signed?(request_with({}), body, "s3cret")
  end

  test "an app webhook carries a JWT signed with the app's client secret" do
    valid = jwt({ exp: 5.minutes.from_now.to_i })

    assert Trackers::Jira::Webhooks.app_signed?(request_with("Authorization" => "Bearer #{valid}"))
    [ jwt({ exp: 5.minutes.from_now.to_i }, secret: "guess"), jwt({ exp: 1.hour.ago.to_i }),
      JSON::JWT.new(exp: 5.minutes.from_now.to_i).to_s, "not-a-jwt" ].each do |token|
      assert_not Trackers::Jira::Webhooks.app_signed?(request_with("Authorization" => "Bearer #{token}")), token
    end
  end

  test "an app delivery reaches the subscriptions holding the webhooks it matched, on the site it came from" do
    acme = create(:integration, :jira_oauth, :active)
    other_site = create(:integration, :jira_oauth, :active)
    other_site.update!(settings: other_site.settings.merge("cloud_id" => "cloud-beta", "site_url" => "https://beta.atlassian.net"))
    ours = create(:tracker_subscription, integration: acme, strategy: "api", provider_subscription_id: "7")
    create(:tracker_subscription, integration: other_site, strategy: "api", provider_subscription_id: "7")

    via_gateway = { "matchedWebhookIds" => [ 7 ], "issue" => { "self" => "https://api.atlassian.com/ex/jira/cloud-acme/rest/api/2/issue/1" } }
    via_site = { "matchedWebhookIds" => [ 7 ], "issue" => { "self" => "https://acme.atlassian.net/rest/api/2/issue/1" } }

    assert_equal [ ours ], Trackers::Jira::Webhooks.app_subscriptions(via_gateway)
    assert_equal [ ours ], Trackers::Jira::Webhooks.app_subscriptions(via_site)
    assert_empty Trackers::Jira::Webhooks.app_subscriptions(via_site.merge("matchedWebhookIds" => [ 8 ]))
  end
end
