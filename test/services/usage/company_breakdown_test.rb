# frozen_string_literal: true

require "test_helper"

class Usage::CompanyBreakdownTest < ActiveSupport::TestCase
  setup do
    @day = Date.new(2026, 10, 14)
    @hour = Time.utc(2026, 10, 14, 10)
    @company = create(:company, :subscribed)
    @owner = create(:user, company: @company)
    @alpha = create(:project, company: @company, owner: @owner, name: "Alpha")
    @beta = create(:project, company: @company, owner: @owner, name: "Beta")
    @pools = {}
  end

  def admission(project, created:, admitted: nil, released: nil)
    pool = @pools[project.id] ||= SessionAdmissionPool.create!(key: "project:#{project.id}", limit: 4, policy_revision: 1)
    session = create(:terminal_session, :agent_session, project: project, user: @owner)
    SessionAdmission.create!(terminal_session: session, session_admission_pool: pool,
                             created_at: created, admitted_at: admitted, released_at: released)
  end

  def breakdown(from: @day, to: @day) = Usage::CompanyBreakdown.new(@company, from: from, to: to).to_h

  def hour_row(hour, **attributes)
    CompanyUsageHour.create!(company: @company, period_start: hour, billing_class: "paying",
                             computed_at: hour + 70.minutes, **attributes)
  end

  test "waits are read per session: the share that waited, their percentiles, and how many were already waiting" do
    admission(@alpha, created: @hour, admitted: @hour, released: @hour + 30.minutes)
    admission(@alpha, created: @hour + 1.minute, admitted: @hour + 30.minutes)
    admission(@alpha, created: @hour + 2.minutes, admitted: @hour + 40.minutes)
    admission(@beta, created: @hour + 3.minutes, admitted: @hour + 50.minutes)

    waits = breakdown[:waits]

    assert_equal 4, waits[:sessions]
    assert_equal 3, waits[:waited]
    assert_equal 33.5.minutes, waits[:p50], "halfway between the two middle waits"
    assert_equal 47.minutes, waits[:max]
    assert_equal 2, waits[:ahead_max], "the Beta session joined behind both Alpha ones"
    assert_in_delta 0.75, waits[:ahead_average]
  end

  test "a session waiting across the range's edge is counted ahead of those behind it, but not as one of its own" do
    admission(@alpha, created: @hour - 11.hours, admitted: @hour + 14.hours)
    admission(@alpha, created: @hour, admitted: @hour + 5.minutes)

    waits = breakdown[:waits]

    assert_equal 1, waits[:sessions]
    assert_equal 1, waits[:ahead_max]
  end

  test "a session admitted the instant another joins is not ahead of it" do
    admission(@alpha, created: @hour - 5.minutes, admitted: @hour)
    admission(@alpha, created: @hour, admitted: @hour)

    assert_equal 0, breakdown[:waits][:ahead_max]
  end

  test "each project shows its own queue limit and the longest line inside it, the most waiting first" do
    SessionConcurrencyLimit.set!(scope: @beta, max_sessions: 1)
    admission(@alpha, created: @hour, admitted: @hour)
    admission(@beta, created: @hour, admitted: @hour + 10.minutes)
    admission(@beta, created: @hour + 1.minute, admitted: @hour + 20.minutes)

    beta, alpha = breakdown[:projects]

    assert_equal [ "Beta", 1, true, 2, 1 ], beta.values_at(:name, :limit, :reserved, :waited, :ahead_max)
    assert_equal [ "Alpha", SessionAdmissionPolicy.scope_default("Project"), false, 0 ],
                 alpha.values_at(:name, :limit, :reserved, :waited)
  end

  test "a workflow run waits for the sum of its steps, each of which queued again" do
    run = create(:workflow_run)
    [ [ @hour, @hour + 2.minutes ], [ @hour + 30.minutes, @hour + 33.minutes ] ].each do |created, admitted|
      session = admission(@alpha, created: created, admitted: admitted).terminal_session
      create(:step_run, workflow_run: run, terminal_session: session)
    end
    admission(@alpha, created: @hour, admitted: @hour + 1.minute)

    runs = breakdown[:runs]

    assert_equal 1, runs[:runs]
    assert_in_delta 2.0, runs[:average_steps]
    assert_equal 5.minutes, runs[:max]
  end

  test "time at capacity is the share of the hours with workers when every one was busy, and waits are read against it" do
    hour_row(@hour, limit_min: 2, limit_max: 2, offered_seconds: 7_200)
    hour_row(@hour + 1.hour, limit_min: 2, limit_max: 2, offered_seconds: 7_200)
    admission(@alpha, created: @hour, admitted: @hour, released: @hour + 40.minutes)
    admission(@alpha, created: @hour + 10.minutes, admitted: @hour + 10.minutes, released: @hour + 30.minutes)
    # Joins while both workers are busy, and takes the one released at :30.
    admission(@alpha, created: @hour + 15.minutes, admitted: @hour + 30.minutes, released: @hour + 50.minutes)
    # Waits with nothing held: not the company's limit, so not at capacity.
    admission(@beta, created: @hour + 70.minutes, admitted: @hour + 75.minutes, released: @hour + 80.minutes)

    capacity = breakdown[:capacity]

    assert_equal 2, capacity[:offered_hours]
    assert_in_delta 30.minutes.to_f / 2.hours, capacity[:time_at_capacity]
    assert_equal [ 2, 1 ], capacity.values_at(:waited, :waited_at_capacity)
  end

  test "a company with no limit has no capacity to be at" do
    hour_row(@hour, unlimited_seconds: 3_600, occupied_seconds: 36_000, peak_workers: 10)
    admission(@alpha, created: @hour, admitted: @hour + 5.minutes, released: @hour + 10.minutes)

    capacity = breakdown[:capacity]

    assert_equal 0, capacity[:offered_hours]
    assert_nil capacity[:time_at_capacity]
  end

  test "each day shows how many of its sessions waited, out of how many, and its p95" do
    admission(@alpha, created: @hour, admitted: @hour + 10.minutes)
    admission(@alpha, created: @hour, admitted: @hour)
    admission(@alpha, created: @hour + 1.day, admitted: @hour + 1.day)

    days = breakdown(to: @day + 1)[:days]

    assert_equal [ "2026-10-14", "2026-10-15" ], days.pluck(:day)
    assert_equal [ 2, 1, 570 ], days.first.values_at(:sessions, :waited, :p95)
    assert_equal [ 1, 0 ], days.last.values_at(:sessions, :waited)
  end

  test "a range with nothing in it reads as empty rather than failing" do
    result = breakdown

    assert_equal 0, result[:waits][:sessions]
    assert_nil result[:waits][:p95]
    assert_equal 0, result[:runs][:runs]
    assert_nil result[:capacity][:time_at_capacity]
    assert_empty result[:projects]
    assert_empty result[:days]
  end
end
