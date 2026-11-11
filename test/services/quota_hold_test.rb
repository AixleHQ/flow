# frozen_string_literal: true

require "test_helper"

class QuotaHoldTest < ActiveSupport::TestCase
  # Stands in for a runtime adapter; each adapter's vendor call is contract-tested on its own.
  class WindowsAdapter
    def initialize(windows) = @windows = windows
    def fetch_subscription_usage(_config) = { status: "ok", windows: @windows }
  end

  setup do
    @user = create(:user, :with_company)
    @credential = create(:agent_credential, user: @user, company: @user.companies.first, agent_type: "kiro_cli")
  end

  def usage(windows)
    Agents::SubscriptionUsageService.new(adapter_resolver: ->(_type) { WindowsAdapter.new(windows) })
  end

  test "holds the credential until the full usage window resets" do
    travel_to Time.utc(2026, 11, 11, 12) do
      windows = [ { key: "kiro_credits", utilization: 100.0, resets_at: "2026-12-01T00:00:00Z" },
                  { key: "other", utilization: 40.0, resets_at: "2026-11-12T00:00:00Z" } ]

      QuotaHold.apply!(@credential, "Out of credits", usage: usage(windows))

      assert_equal Time.utc(2026, 12, 1), @credential.reload.quota_exhausted_until
      assert @credential.quota_exhausted?
    end
  end

  test "without a full window, holds until the date the CLI printed, else for an hour" do
    travel_to Time.utc(2026, 11, 11, 12) do
      QuotaHold.apply!(@credential, "You've hit your limit. You will regain access on Nov 14 at 9am (UTC).", usage: usage([]))
      assert_equal Time.utc(2026, 11, 14, 9), @credential.reload.quota_exhausted_until

      QuotaHold.apply!(@credential, "Usage limit reached", usage: usage([]))
      assert_equal Time.utc(2026, 11, 11, 13), @credential.reload.quota_exhausted_until
    end
  end

  test "a new sign-in lifts the hold" do
    @credential.update_column(:quota_exhausted_until, 1.day.from_now)

    AgentCredential.from_artifacts(@user.id, @credential.company_id, "kiro_cli", { "token" => "new" }, new_authorization: true)

    assert_nil @credential.reload.quota_exhausted_until
  end
end
