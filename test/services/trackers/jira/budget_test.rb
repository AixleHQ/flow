# frozen_string_literal: true

require "test_helper"

# Jira's app-wide rate-limit pool (docs/design/tracker-attachments.md §10.1).
class Trackers::Jira::BudgetTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
  end

  test "a service account's traffic is kept apart from the app's shared pool" do
    app = create(:integration, :jira_oauth, :active)
    account = create(:integration, :jira, :active)

    assert_equal "jira:app", Trackers::Jira::Budget.pool_for(app)
    assert_equal "jira:service_account:#{account.id}", Trackers::Jira::Budget.pool_for(account)
  end

  test "the latest response says whether the pool is near its limit" do
    Trackers::Jira::Budget.observe("jira:app", { "x-ratelimit-remaining" => "900", "x-ratelimit-nearlimit" => "true" })
    assert Trackers::Jira::Budget.near_limit?("jira:app")

    Trackers::Jira::Budget.observe("jira:app", { "x-ratelimit-remaining" => "40000", "x-ratelimit-nearlimit" => "false" })
    assert_not Trackers::Jira::Budget.near_limit?("jira:app")
    assert_equal 40_000, Trackers::Jira::Budget.state("jira:app")["remaining"]
  end

  test "background work takes at most its share per connection per hour" do
    integration = create(:integration, :jira, :active)

    assert Trackers::Jira::Budget.take(integration, Trackers::Jira::Budget::JOB_SHARE_PER_HOUR)
    assert_not Trackers::Jira::Budget.take(integration)
    travel 1.hour
    assert Trackers::Jira::Budget.take(integration)
  end
end
