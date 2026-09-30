# frozen_string_literal: true

require "test_helper"

module Activities
  module Trackers
    class RefreshSubscriptionsActivityTest < ActiveSupport::TestCase
      setup do
        with_jira_oauth_app
        @jira = stub_jira!
      end

      test "webhooks that expire within a week are extended; the rest are left alone" do
        integration = create(:integration, :jira_oauth, :active)
        due = ::Trackers::Jira::Subscriptions.new(integration).ensure!
        due.update!(expires_at: 3.days.from_now)
        later = create(:tracker_subscription, integration: create(:integration, :jira_oauth, :active), strategy: "api",
                                              provider_subscription_id: "9", expires_at: 20.days.from_now)

        result = run_activity(RefreshSubscriptionsActivity)

        assert_equal [ 1, 0 ], result.values_at(:refreshed, :errors)
        assert_in_delta 30.days.from_now, due.reload.expires_at, 1.minute
        assert_in_delta 20.days.from_now, later.reload.expires_at, 1.minute
      end

      test "a 3LO grant idle for a month is renewed, before Atlassian retires it" do
        idle = create(:integration, :jira_oauth, :active)
        idle.update!(credentials_data: idle.credentials_data.merge("expires_at" => 40.days.ago.iso8601))
        create(:integration, :jira_oauth, :active)
        stub_request(:post, "#{JIRA_AUTH}/oauth/token").with(body: hash_including("refresh_token" => "jira-refresh"))
          .to_return(status: 200, body: { access_token: "fresh", refresh_token: "rt-new", expires_in: 3600 }.to_json)

        result = run_activity(RefreshSubscriptionsActivity)

        assert_equal 1, result[:renewed_grants]
        assert_equal "rt-new", idle.reload.credentials_data["refresh_token"]
      end
    end
  end
end
