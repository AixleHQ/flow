# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261029120000_backfill_the_capacity_log")

# The backfill gives a company the log never knew an opening entry. What it
# must not do is date that entry inside the hour it runs in: the window reads a
# company whose first entry lands mid-hour as having opened the hour at
# nothing, so the deploy hour -- and, for a deploy in the first minutes of an
# hour, the one before it -- would be billed short.
#
# Measured against the real clock, not a travelled one: the migration dates
# nothing in Ruby, and `travel_to` leaves the database's NOW() where it was.
class BackfillTheCapacityLogTest < ActiveSupport::TestCase
  setup do
    @migration = BackfillTheCapacityLog.new
    @hour = Time.current.utc.beginning_of_hour
    # A company whose limit was set before the log shipped: the live row says
    # two, the log says nothing at all.
    @company = create(:company, created_at: @hour - 3.days)
    SessionConcurrencyLimit.create!(scope_type: "Company", scope_id: @company.id, max_sessions: 2)
    CompanyCapacityChange.where(company_id: @company.id).delete_all
  end

  def migrate = @migration.suppress_messages { @migration.up }

  def minutes_for(hour) = Billing::CapacityWindow.for_hour(hour).per_company.fetch(@company.id, 0) / 60

  test "a company the log never knew is billed the whole of the hour the backfill ran in, and the one before" do
    migrate

    assert_equal 120, minutes_for(@hour), "the hour the deploy landed in"
    assert_equal 120, minutes_for(@hour - 1.hour), "the hour before it, measured minutes after the deploy"
  end

  test "it writes nothing for a company already in the log" do
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 5, occurred_at: @hour - 1.day)

    assert_no_difference -> { CompanyCapacityChange.count } do
      migrate
    end
  end
end
