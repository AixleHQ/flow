# frozen_string_literal: true

require "test_helper"

class TrackerAccountTest < ActiveSupport::TestCase
  test "remembering an id twice keeps one row and moves its last sighting" do
    freeze_time
    TrackerAccount.remember!(provider: "jira", account_ids: [ "557058:ada", "", nil, "557058:ada" ])
    travel 1.day
    TrackerAccount.remember!(provider: "jira", account_ids: [ "557058:ada" ])

    account = TrackerAccount.sole
    assert_equal [ "557058:ada", 1.day.ago, Time.current ], [ account.account_id, account.first_seen_at, account.last_seen_at ]
  end

  test "an account is due when it was never reported or its cycle has passed" do
    never = create_account("a")
    stale = create_account("b", reported_at: 8.days.ago)
    create_account("c", reported_at: 1.day.ago)
    create_account("d", status: "closed")

    assert_equal [ never, stale ], TrackerAccount.due(7.days).order(:id).to_a
  end

  def create_account(id, **attributes)
    TrackerAccount.create!(provider: "jira", account_id: id, first_seen_at: Time.current, last_seen_at: Time.current, **attributes)
  end
end
