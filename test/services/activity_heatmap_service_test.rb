# frozen_string_literal: true

require "test_helper"

class ActivityHeatmapServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @other = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  def seed_session(user: @user, project: @project, session_type: "agent_session",
                   agent_type: "claude_code", created_at: Time.current)
    session = build(:terminal_session, user:, project:, session_type:, agent_type:, created_at:)
    session.save!(validate: false)
    session
  end

  test "groups sessions into one count per calendar day" do
    seed_session(created_at: Time.current.utc.change(hour: 9))
    seed_session(created_at: Time.current.utc.change(hour: 15))
    seed_session(created_at: 2.days.ago)

    days = ActivityHeatmapService.new(scope: @user.terminal_sessions).call

    today = Time.current.utc.to_date.iso8601
    today_bucket = days.find { |d| d.date == today }
    assert { today_bucket.count == 2 }
    assert { days.sum(&:count) == 3 }
    assert { days.all? { |d| d.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end

  test "counts workflow_step sessions even when agent_type is nil" do
    seed_session(session_type: "workflow_step", agent_type: nil)

    days = ActivityHeatmapService.new(scope: @user.terminal_sessions).call

    assert { days.sum(&:count) == 1 }
  end

  test "excludes auth_setup and tool_setup sessions" do
    seed_session(session_type: "agent_session")
    seed_session(session_type: "auth_setup", project: nil)
    seed_session(session_type: "tool_setup")

    days = ActivityHeatmapService.new(scope: @user.terminal_sessions).call

    assert { days.sum(&:count) == 1 }
  end

  test "excludes sessions older than the window" do
    seed_session(created_at: 400.days.ago)

    days = ActivityHeatmapService.new(scope: @user.terminal_sessions, days: 365).call

    assert { days.empty? }
  end

  test "scope agnostic: honors project and participant scoping" do
    seed_session(user: @user, project: @project)
    seed_session(user: @other, project: @project)

    project_days = ActivityHeatmapService.new(scope: @project.terminal_sessions).call
    assert { project_days.sum(&:count) == 2 }

    participant_days = ActivityHeatmapService.new(scope: @project.terminal_sessions.where(user_id: @user.id)).call
    assert { participant_days.sum(&:count) == 1 }
  end
end
