# frozen_string_literal: true

require "test_helper"

class SessionCostTokenUsageServiceTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @admin    = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project  = create(:project, company: @company, owner: @admin)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_session_with_usage(project:, user:, cost_cents:, total_tokens:, created_at: Time.current)
    create(:terminal_session,
      project: project,
      user: user,
      session_type: "agent_session",
      cost_cents: cost_cents,
      total_tokens: total_tokens,
      created_at: created_at)
  end

  def create_session_linked_to_task(project:, user:, cost_cents:, total_tokens:, board_task:, created_at: Time.current)
    session = create_session_with_usage(project: project, user: user, cost_cents: cost_cents, total_tokens: total_tokens, created_at: created_at)
    workflow = create(:workflow, :with_company_scope, scope: @company)
    step = create(:step, workflow: workflow)
    run = create(:workflow_run, workflow: workflow, project: project, user: user, board_task: board_task)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    session
  end

  def call_service(scope:, period: "30d", user: @admin, project: @project, tags: nil, task_type: nil)
    SessionCostTokenUsageService.new(
      project: project,
      user: user,
      scope: scope,
      period: period,
      tags: tags,
      task_type: task_type
    ).call
  end

  # ─── Scope: project ──────────────────────────────────────────────────────────

  test "project scope returns sessions for the given project only" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 500)

    other_project = create(:project, company: @company, owner: @admin)
    create_session_with_usage(project: other_project, user: @admin, cost_cents: 999, total_tokens: 9999)

    result = call_service(scope: "project")

    assert { result.totals.total_cost_cents == 100 }
    assert { result.totals.total_tokens == 500 }
  end

  test "project scope excludes sessions outside the period window" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 200,
      created_at: 60.days.ago)

    result = call_service(scope: "project", period: "30d")

    assert { result.totals.total_cost_cents == 0 }
    assert { result.totals.total_tokens == 0 }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's sessions in the project" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 300)
    create_session_with_usage(project: @project, user: @employee, cost_cents: 500, total_tokens: 600)

    result = call_service(scope: "user", user: @admin)

    assert { result.totals.total_cost_cents == 200 }
    assert { result.totals.total_tokens == 300 }
  end

  # ─── Aggregate totals ────────────────────────────────────────────────────────

  test "totals sums cost and tokens across all sessions" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100)

    result = call_service(scope: "project")

    assert { result.totals.total_cost_cents == 150 }
    assert { result.totals.total_tokens == 300 }
  end

  test "avg_cost_cents_per_session is calculated correctly" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 400)

    result = call_service(scope: "project")

    assert { result.totals.avg_cost_cents_per_session == 150 }
  end

  test "avg_cost_cents_per_session is zero when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.totals.avg_cost_cents_per_session == 0 }
  end

  # ─── Time series bucketing ───────────────────────────────────────────────────

  test "returns daily time series points for 7d period" do
    3.times do |i|
      create_session_with_usage(project: @project, user: @admin, cost_cents: 10, total_tokens: 50,
        created_at: i.days.ago)
    end

    result = call_service(scope: "project", period: "7d")

    assert { result.time_series.length == 3 }
    assert { result.time_series.all? { |p| p.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end

  test "returns monthly time series points for 1y period" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 500,
      created_at: 1.month.ago)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 800,
      created_at: Time.current)

    result = call_service(scope: "project", period: "1y")

    assert { result.time_series.length == 2 }
  end

  test "aggregates multiple sessions on the same day into one time series point" do
    2.times do
      create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100,
        created_at: Time.current)
    end

    result = call_service(scope: "project", period: "7d")

    assert { result.time_series.length == 1 }
    assert { result.time_series.first.cost_cents == 100 }
    assert { result.time_series.first.total_tokens == 200 }
  end

  test "returns empty time series and zero totals when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.time_series.empty? }
    assert { result.totals.total_cost_cents == 0 }
    assert { result.totals.total_tokens == 0 }
  end

  # ─── Task filters ────────────────────────────────────────────────────────────

  test "tag filter includes only sessions whose board task has a matching tag" do
    board  = create(:board, project: @project)
    column = create(:board_column, board: board)
    matching_task = create(:board_task, board: board, board_column: column, tags: [ "analytics", "backend" ])
    other_task    = create(:board_task, board: board, board_column: column, tags: [ "frontend" ])

    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 100, total_tokens: 200, board_task: matching_task)
    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 999, total_tokens: 999, board_task: other_task)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100)

    result = call_service(scope: "project", tags: [ "analytics" ])

    assert { result.totals.total_cost_cents == 100 }
    assert { result.totals.total_tokens == 200 }
  end

  test "task_type filter includes only sessions whose board task matches the type" do
    board  = create(:board, project: @project)
    column = create(:board_column, board: board)
    epic_task  = create(:board_task, board: board, board_column: column, task_type: :epic)
    story_task = create(:board_task, board: board, board_column: column, task_type: :story)

    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 200, total_tokens: 300, board_task: epic_task)
    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 999, total_tokens: 999, board_task: story_task)

    result = call_service(scope: "project", task_type: "epic")

    assert { result.totals.total_cost_cents == 200 }
    assert { result.totals.total_tokens == 300 }
  end

  test "combined tag and task_type filter applies AND semantics" do
    board  = create(:board, project: @project)
    column = create(:board_column, board: board)
    matching_task    = create(:board_task, board: board, board_column: column, tags: [ "analytics" ], task_type: :epic)
    tag_only_task    = create(:board_task, board: board, board_column: column, tags: [ "analytics" ], task_type: :story)
    type_only_task   = create(:board_task, board: board, board_column: column, tags: [ "backend" ],   task_type: :epic)

    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 100, total_tokens: 200, board_task: matching_task)
    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 999, total_tokens: 999, board_task: tag_only_task)
    create_session_linked_to_task(project: @project, user: @admin, cost_cents: 999, total_tokens: 999, board_task: type_only_task)

    result = call_service(scope: "project", tags: [ "analytics" ], task_type: "epic")

    assert { result.totals.total_cost_cents == 100 }
    assert { result.totals.total_tokens == 200 }
  end

  test "no filter active returns all sessions unchanged" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100)

    result = call_service(scope: "project")

    assert { result.totals.total_cost_cents == 150 }
    assert { result.totals.total_tokens == 300 }
  end

  test "tag filter returns empty result when project has no board" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)

    result = call_service(scope: "project", tags: [ "analytics" ])

    assert { result.totals.total_cost_cents == 0 }
    assert { result.totals.total_tokens == 0 }
  end
end
