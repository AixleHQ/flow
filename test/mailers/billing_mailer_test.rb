# frozen_string_literal: true

require "test_helper"

class BillingMailerTest < ActionMailer::TestCase
  setup do
    @company = create(:company, name: "Acme Robotics")
    @actor = create(:user, name: "Dana Admin", company: @company, membership_role: "admin")
    @cancellation = create(:billing_cancellation, company: @company, user: @actor,
                                                  cancels_at: Time.zone.parse("2026-11-01 00:00"))
  end

  test "it tells another admin who cancelled, that access has stopped, and what is kept" do
    other = create(:user, email: "other-admin@example.com", company: @company, membership_role: "admin")

    email = BillingMailer.subscription_cancelled(@cancellation, other)

    assert_equal [ "other-admin@example.com" ], email.to
    assert_match(/is cancelled/, email.subject)
    [ email.text_part.decoded, email.html_part.decoded ].each do |body|
      assert_includes body, "Dana Admin cancelled"
      assert_includes body, "November 1, 2026"
      assert_includes body, "No new sessions start"
      assert_includes body, "billed on the final invoice"
      assert_includes body, "history are kept"
      assert_includes body, "/company/settings/billing"
    end
  end

  test "it tells the admin who cancelled that they did" do
    email = BillingMailer.subscription_cancelled(@cancellation, @actor)

    assert_includes email.text_part.decoded, "You cancelled"
  end
end
