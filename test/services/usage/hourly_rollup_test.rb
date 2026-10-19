# frozen_string_literal: true

require "test_helper"

class Usage::HourlyRollupTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @hour = Time.utc(2026, 10, 14, 10)
    @company = create(:company, :subscribed)
    @owner = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @pool = SessionAdmissionPool.create!(key: "project:#{@project.id}", limit: 10, policy_revision: 1)
    limit(@company, 4, @hour - 1.day)
  end

  def limit(company, max_sessions, at)
    CompanyCapacityChange.record!(company_id: company.id, max_sessions: max_sessions, occurred_at: at)
  end

  def admission(created:, admitted: nil, released: nil, project: @project, pool: @pool)
    session = create(:terminal_session, :agent_session, project: project, user: @owner)
    SessionAdmission.create!(terminal_session: session, session_admission_pool: pool,
                             created_at: created, admitted_at: admitted, released_at: released)
  end

  def roll_up(from: @hour, to: @hour + 1.hour, now: @hour + 70.minutes)
    Usage::HourlyRollup.call(from: from, to: to, now: now)
  end

  def row(company = @company, hour = @hour)
    CompanyUsageHour.find_by!(company: company, period_start: hour)
  end

  test "a worker counts for the part of the hour it was held, and the peak is the most held at once" do
    admission(created: @hour - 40.minutes, admitted: @hour - 30.minutes, released: @hour + 30.minutes)
    admission(created: @hour + 15.minutes, admitted: @hour + 15.minutes)
    # Admitted the instant the first one is released: a hand-over, not a third worker.
    admission(created: @hour + 10.minutes, admitted: @hour + 30.minutes, released: @hour + 45.minutes)

    roll_up

    assert_equal 30.minutes + 45.minutes + 15.minutes, row.occupied_seconds
    assert_equal 2, row.peak_workers
  end

  test "a wait is counted in the hour the session was admitted, and a session still waiting is only queued" do
    admission(created: @hour - 10.minutes, admitted: @hour + 5.minutes)
    admission(created: @hour + 20.minutes, admitted: @hour + 21.minutes)
    admission(created: @hour + 50.minutes)
    admission(created: @hour - 3.hours, admitted: @hour - 2.hours, released: @hour - 1.hour)

    roll_up

    assert_equal 2, row.sessions_queued, "only the ones created during the hour"
    assert_equal 2, row.sessions_admitted
    assert_equal 15.minutes + 1.minute, row.wait_seconds_total
    assert_equal 15.minutes, row.wait_seconds_max
  end

  test "an agent login holds no worker, because it draws on no company's budget" do
    login = create(:terminal_session, :auth_setup, company_id: @company.id, user: @owner)
    pool = SessionAdmissionPool.create!(key: "user:#{@owner.id}", limit: 2, policy_revision: 1)
    SessionAdmission.create!(terminal_session: login, session_admission_pool: pool,
                             created_at: @hour, admitted_at: @hour)

    roll_up

    assert_equal 0, row.occupied_seconds
    assert_equal 0, row.sessions_queued
  end

  test "sessions are counted on the hour they ended, and only the ones that ran work" do
    create(:terminal_session, :agent_session, project: @project, user: @owner,
                                              state: "finished", finished_at: @hour + 10.minutes)
    create(:terminal_session, project: @project, user: @owner, session_type: "workflow_step",
                              state: "failed", finished_at: @hour + 20.minutes)
    create(:terminal_session, :agent_session, project: @project, user: @owner,
                                              state: "cancelled", finished_at: @hour + 30.minutes)
    create(:terminal_session, :auth_setup, company_id: @company.id, user: @owner,
                                           state: "finished", finished_at: @hour + 40.minutes)
    create(:terminal_session, :agent_session, project: @project, user: @owner,
                                              state: "finished", finished_at: @hour + 61.minutes)

    roll_up

    assert_equal 1, row.sessions_succeeded
    assert_equal 1, row.sessions_failed
  end

  test "the limit is reported as its smallest and largest value, and the time without one" do
    limit(@company, 6, @hour + 15.minutes)
    limit(@company, nil, @hour + 45.minutes)

    roll_up

    assert_equal 4, row.limit_min
    assert_equal 6, row.limit_max
    assert_equal 15.minutes, row.unlimited_seconds
  end

  test "a company with no limit is still measured, and says so" do
    unlimited = create(:company)
    project = create(:project, company: unlimited, owner: create(:user, company: unlimited))
    pool = SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 10, policy_revision: 1)
    admission(created: @hour, admitted: @hour, released: @hour + 20.minutes, project: project, pool: pool)

    roll_up

    measured = row(unlimited)
    assert_nil measured.limit_max
    assert_equal 1.hour, measured.unlimited_seconds
    assert_equal 20.minutes, measured.occupied_seconds
    assert_equal 0, measured.offered_seconds
    assert_equal "unlimited", measured.billing_class
  end

  test "offered seconds are what the billing ledger recorded, not a second measurement" do
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: @hour, quantity_seconds: 7_200)

    roll_up

    assert_equal 7_200, row.offered_seconds
  end

  test "the billing class says whether an hour is billed, and why not" do
    companies = {
      "paying" => @company,
      "managed" => create(:company, :managed_by_aixle),
      "trial" => create(:company, :trialing),
      "blocked" => create(:company, :billing_blocked),
      "no_customer" => create(:company)
    }
    companies.each_value { |company| limit(company, 2, @hour - 1.day) }

    roll_up

    companies.each { |expected, company| assert_equal expected, row(company).billing_class, company.name }
  end

  test "outside the hosted product the class follows the deployment" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))
    roll_up
    assert_equal "not_metered", row.billing_class

    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::AWS_MARKETPLACE))
    roll_up
    assert_equal "paying", row.billing_class
  end

  test "every active company gets a row each hour; a suspended one only for an hour it still used" do
    idle = create(:company)
    suspended = create(:company)
    suspended.suspend!
    stopped = create(:company)
    project = create(:project, company: stopped, owner: create(:user, company: stopped))
    pool = SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 10, policy_revision: 1)
    admission(created: @hour - 1.hour, admitted: @hour - 1.hour, released: @hour + 5.minutes,
              project: project, pool: pool)
    stopped.suspend!

    roll_up

    assert_equal 0, row(idle).occupied_seconds
    assert_not CompanyUsageHour.exists?(company: suspended)
    assert_equal "inactive", row(stopped).billing_class
    assert_equal 5.minutes, row(stopped).occupied_seconds
  end

  test "measuring an hour again rewrites its row with the current answer" do
    held = admission(created: @hour, admitted: @hour)
    roll_up
    assert_equal 1.hour, row.occupied_seconds

    held.update!(released_at: @hour + 10.minutes)

    assert_no_difference -> { CompanyUsageHour.count } do
      roll_up
    end
    assert_equal 10.minutes, row.occupied_seconds
  end

  test "only closed hours are measured, and by default the last three" do
    result = Usage::HourlyRollup.call(now: @hour + 30.minutes)

    assert_equal (@hour - 3.hours).iso8601, result[:from]
    assert_equal @hour.iso8601, result[:to]
    assert_equal [ @hour - 3.hours, @hour - 2.hours, @hour - 1.hour ],
                 CompanyUsageHour.where(company: @company).order(:period_start).pluck(:period_start)

    roll_up(from: @hour, to: @hour + 5.hours, now: @hour + 2.hours + 10.minutes)

    assert_equal @hour + 1.hour, CompanyUsageHour.where(company: @company).maximum(:period_start)
  end

  test "the first run measures every hour since the first admission, so history needs no backfill" do
    admission(created: @hour - 2.days + 30.minutes, admitted: @hour - 2.days + 30.minutes,
              released: @hour - 2.days + 45.minutes)

    result = Usage::HourlyRollup.call(now: @hour + 10.minutes)

    assert_equal (@hour - 2.days).iso8601, result[:from]
    assert_equal 48, CompanyUsageHour.where(company: @company).count
    assert_equal 15.minutes, row(@company, @hour - 2.days).occupied_seconds
  end

  test "hours missed while the worker was down are measured on the next run" do
    roll_up(from: @hour - 10.hours, to: @hour - 6.hours, now: @hour)

    result = Usage::HourlyRollup.call(now: @hour + 10.minutes)

    assert_equal (@hour - 6.hours).iso8601, result[:from]
    assert_equal 10, CompanyUsageHour.where(company: @company).count
  end

  test "a range longer than a day is measured whole" do
    result = roll_up(from: @hour - 30.hours, to: @hour + 1.hour)

    assert_equal 31, CompanyUsageHour.where(company: @company).count
    assert_operator result[:rows], :>=, 31
  end
end
