# frozen_string_literal: true

require "test_helper"

module Activities
  module Trackers
    class ReportPersonalDataActivityTest < ActiveSupport::TestCase
      test "week-old deliveries are dropped and the report runs" do
        subscription = create(:tracker_subscription)
        old = TrackerDelivery.record(subscription: subscription, dedup_key: "old", notifications: [])
        old.update_columns(created_at: 8.days.ago)
        fresh = TrackerDelivery.record(subscription: subscription, dedup_key: "fresh", notifications: [])

        result = run_activity(ReportPersonalDataActivity)

        assert_equal [ 1, "no_oauth_app" ], result.values_at(:purged_deliveries, :skipped)
        assert_equal [ fresh.id ], TrackerDelivery.pluck(:id)
      end
    end
  end
end
