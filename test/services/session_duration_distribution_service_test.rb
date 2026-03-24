# frozen_string_literal: true

require "test_helper"

class SessionDurationDistributionServiceTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @admin    = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project  = create(:project, company: @company, owner: @admin)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_finished_session(project:, user:, duration_seconds:, created_at: Time.current)
    started_at  = created_at - duration_seconds.seconds
    finished_at = created_at
    create(:terminal_session,
      project: project,
      user: user,
      session_type: "agent_session",
      started_at: started_at,
      finished_at: finished_at,
      created_at: created_at)
  end

  def call_service(scope:, period: "30d", user: @admin, project: @project)
    SessionDurationDistributionService.new(
      project: project,
      user: user,
      scope: scope,
      period: period
    ).call
  end

  def bucket_count(result, range)
    result.buckets.find { |b| b.range == range }&.count || 0
  end

  # ─── Scope: project ──────────────────────────────────────────────────────────

  test "project scope returns sessions for the given project only" do
    create_finished_session(project: @project, user: @admin, duration_seconds: 30)

    other_project = create(:project, company: @company, owner: @admin)
    create_finished_session(project: other_project, user: @admin, duration_seconds: 30)

    result = call_service(scope: "project")

    assert { bucket_count(result, "0\u20131 min") == 1 }
    assert { result.buckets.sum(&:count) == 1 }
  end

  test "project scope excludes sessions outside the period window" do
    create_finished_session(project: @project, user: @admin, duration_seconds: 30, created_at: 60.days.ago)

    result = call_service(scope: "project", period: "30d")

    assert { result.buckets.sum(&:count) == 0 }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's sessions" do
    create_finished_session(project: @project, user: @admin, duration_seconds: 30)
    create_finished_session(project: @project, user: @employee, duration_seconds: 200)

    result = call_service(scope: "user", user: @admin)

    assert { result.buckets.sum(&:count) == 1 }
    assert { bucket_count(result, "0\u20131 min") == 1 }
  end

  # ─── Scope: company ──────────────────────────────────────────────────────────

  test "company scope aggregates sessions across all company projects" do
    other_project = create(:project, company: @company, owner: @admin)

    create_finished_session(project: @project, user: @admin, duration_seconds: 30)
    create_finished_session(project: other_project, user: @employee, duration_seconds: 30)

    result = call_service(scope: "company")

    assert { bucket_count(result, "0\u20131 min") == 2 }
  end

  test "company scope excludes sessions from other companies" do
    other_company = create(:company)
    other_user    = create(:user, :admin, company: other_company)
    other_project = create(:project, company: other_company, owner: other_user)
    create_finished_session(project: other_project, user: other_user, duration_seconds: 30)

    create_finished_session(project: @project, user: @admin, duration_seconds: 200)

    result = call_service(scope: "company")

    assert { result.buckets.sum(&:count) == 1 }
    assert { bucket_count(result, "1\u20135 min") == 1 }
  end

  # ─── Bucket assignment ───────────────────────────────────────────────────────

  test "assigns sessions to the correct buckets based on duration" do
    create_finished_session(project: @project, user: @admin, duration_seconds: 30)    # 0–1 min
    create_finished_session(project: @project, user: @admin, duration_seconds: 120)   # 1–5 min
    create_finished_session(project: @project, user: @admin, duration_seconds: 600)   # 5–15 min
    create_finished_session(project: @project, user: @admin, duration_seconds: 1200)  # 15–30 min
    create_finished_session(project: @project, user: @admin, duration_seconds: 2400)  # 30–60 min
    create_finished_session(project: @project, user: @admin, duration_seconds: 7200)  # 60+ min

    result = call_service(scope: "project")

    assert { bucket_count(result, "0\u20131 min")   == 1 }
    assert { bucket_count(result, "1\u20135 min")   == 1 }
    assert { bucket_count(result, "5\u201315 min")  == 1 }
    assert { bucket_count(result, "15\u201330 min") == 1 }
    assert { bucket_count(result, "30\u201360 min") == 1 }
    assert { bucket_count(result, "60+ min")        == 1 }
  end

  test "always returns all 6 buckets even when some are empty" do
    create_finished_session(project: @project, user: @admin, duration_seconds: 30)

    result = call_service(scope: "project")

    assert { result.buckets.size == 6 }
  end

  test "excludes sessions with nil started_at or finished_at" do
    create(:terminal_session, project: @project, user: @admin, session_type: "agent_session",
      started_at: nil, finished_at: Time.current)
    create(:terminal_session, project: @project, user: @admin, session_type: "agent_session",
      started_at: Time.current, finished_at: nil)

    result = call_service(scope: "project")

    assert { result.buckets.sum(&:count) == 0 }
  end

  test "returns empty buckets when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.buckets.size == 6 }
    assert { result.buckets.all? { |b| b.count == 0 } }
  end
end
