# frozen_string_literal: true

require "test_helper"

class SessionSourceBreakdownServiceTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @admin    = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project  = create(:project, company: @company, owner: @admin)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_session(project:, user:, session_type:, created_at: Time.current)
    build(:terminal_session, project: project, user: user, session_type: session_type, created_at: created_at).tap do |s|
      s.save!(validate: false)
    end
  end

  def call_service(scope:, period: "30d", user: @admin, project: @project)
    SessionSourceBreakdownService.new(
      project: project,
      user: user,
      scope: scope,
      period: period
    ).call
  end

  # ─── Scope: project ──────────────────────────────────────────────────────────

  test "project scope returns sessions for the given project only" do
    create_session(project: @project, user: @admin, session_type: "agent_session")

    other_project = create(:project, company: @company, owner: @admin)
    create_session(project: other_project, user: @admin, session_type: "workflow_step")

    result = call_service(scope: "project")

    assert { result.sources.size == 1 }
    assert { result.sources.first.session_type == "agent_session" }
    assert { result.sources.first.count == 1 }
  end

  test "project scope excludes sessions outside the period window" do
    create_session(project: @project, user: @admin, session_type: "agent_session", created_at: 60.days.ago)

    result = call_service(scope: "project", period: "30d")

    assert { result.sources.empty? }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's sessions in the project" do
    create_session(project: @project, user: @admin, session_type: "agent_session")
    create_session(project: @project, user: @employee, session_type: "workflow_step")

    result = call_service(scope: "user", user: @admin)

    assert { result.sources.size == 1 }
    assert { result.sources.first.session_type == "agent_session" }
    assert { result.sources.first.count == 1 }
  end

  # ─── Label mapping ───────────────────────────────────────────────────────────

  test "maps known session types to human-readable labels" do
    create_session(project: @project, user: @admin, session_type: "agent_session")
    create_session(project: @project, user: @admin, session_type: "workflow_step")

    result = call_service(scope: "project")

    labels = result.sources.map(&:label)
    assert { labels.include?("Standalone") }
    assert { labels.include?("From Workflows") }
  end

  test "humanizes unknown session types as fallback label" do
    create_session(project: @project, user: @admin, session_type: "unknown_type")

    result = call_service(scope: "project")

    assert { result.sources.first.label == "Unknown type" }
  end

  # ─── Aggregation ─────────────────────────────────────────────────────────────

  test "counts multiple sessions of the same type correctly" do
    3.times { create_session(project: @project, user: @admin, session_type: "agent_session") }
    2.times { create_session(project: @project, user: @admin, session_type: "workflow_step") }

    result = call_service(scope: "project")

    agent_row    = result.sources.find { |s| s.session_type == "agent_session" }
    workflow_row = result.sources.find { |s| s.session_type == "workflow_step" }

    assert { agent_row.count == 3 }
    assert { workflow_row.count == 2 }
  end

  test "returns empty sources when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.sources.empty? }
  end
end
