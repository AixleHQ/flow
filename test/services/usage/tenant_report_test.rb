# frozen_string_literal: true

require "test_helper"

class Usage::TenantReportTest < ActiveSupport::TestCase
  setup do
    @day = Time.utc(2026, 10, 14)
    @acme = create(:company, name: "Acme")
    @globex = create(:company, name: "Globex")
  end

  def hour(company, at, **attributes)
    CompanyUsageHour.create!(company: company, period_start: at, billing_class: "paying",
                             computed_at: at + 70.minutes, **attributes)
  end

  test "a day sums its hours, keeps the extremes, and takes the billing class of its last hour" do
    hour(@acme, @day + 9.hours, offered_seconds: 3_600, occupied_seconds: 1_800, limit_min: 1, limit_max: 1,
                                peak_workers: 1, sessions_admitted: 2, wait_seconds_total: 30, wait_seconds_max: 20,
                                sessions_succeeded: 2, billing_class: "trial")
    hour(@acme, @day + 10.hours, offered_seconds: 7_200, occupied_seconds: 3_600, limit_min: 2, limit_max: 3,
                                 peak_workers: 3, sessions_admitted: 1, wait_seconds_total: 90, wait_seconds_max: 90,
                                 sessions_failed: 1, billing_class: "paying")

    day = Usage::TenantReport.new(now: @day + 1.day).to_h[:days].sole

    assert_equal "2026-10-14", day[:day]
    assert_equal 2, day[:hours]
    assert_equal 10_800, day[:offered_seconds]
    assert_equal 5_400, day[:occupied_seconds]
    assert_equal 1, day[:limit_min]
    assert_equal 3, day[:limit_max]
    assert_equal 3, day[:peak_workers]
    assert_equal 3, day[:sessions_admitted]
    assert_equal 120, day[:wait_seconds_total]
    assert_equal 90, day[:wait_seconds_max]
    assert_equal 2, day[:sessions_succeeded]
    assert_equal 1, day[:sessions_failed]
    assert_equal "paying", day[:billing_class]
  end

  test "days are split at UTC midnight, per company, with the tenants they belong to" do
    hour(@acme, @day + 23.hours)
    hour(@acme, @day + 1.day)
    hour(@globex, @day + 1.day + 5.hours)

    report = Usage::TenantReport.new(now: @day + 2.days).to_h

    assert_equal [ [ @acme.id, "2026-10-14" ], [ @acme.id, "2026-10-15" ], [ @globex.id, "2026-10-15" ] ],
                 report[:days].map { |day| [ day[:company_id], day[:day] ] }
    assert_equal [ { id: @acme.id, name: "Acme" }, { id: @globex.id, name: "Globex" } ], report[:tenants]
    assert_equal "2026-10-15T06:00:00Z", report[:measured_through]
  end

  test "the platform's size counts what is live: active companies, their active members and projects" do
    owner = create(:user, company: @acme)
    create(:user, company: @acme, membership_state: "revoked")
    create(:user, company: @acme).update_column(:deleted_at, Time.current)
    create(:user, company: @globex)
    create(:project, company: @acme, owner: owner)
    create(:project, company: @acme, owner: owner, state: :archived)
    @globex.suspend!

    snapshot = Usage::TenantReport.new(now: @day).to_h[:snapshot]

    assert_equal({ companies: 1, members: 1, projects: 1 }, snapshot)
  end

  test "history older than the report carries is left out" do
    hour(@acme, @day - Usage::TenantReport::HISTORY - 1.day)

    report = Usage::TenantReport.new(now: @day).to_h

    assert_empty report[:days]
    assert_empty report[:tenants]
  end
end
