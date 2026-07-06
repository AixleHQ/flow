# frozen_string_literal: true

require "test_helper"

class RecentActivityServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @board_column = create(:board_column, board: @board)
    @workflow = create(:workflow, :with_company_scope, scope: @company)
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  def create_board_activity(event_type:, board: @board, board_task: nil, actor: @user,
                            actor_type: "human", metadata: {}, created_at: Time.current)
    BoardActivity.create!(
      event_type:, board:, board_task:, actor:, actor_type:, metadata:, created_at:
    )
  end

  def create_agent_session(state:, user: @user, project: nil, agent_type: "claude_code",
                           created_at: Time.current)
    create(
      :terminal_session, :agent_session,
      state:, user:, project:, agent_type:, created_at:
    )
  end

  def create_run(state:, project: @project, user: @user, workflow: @workflow,
                 created_at: Time.current)
    create(:workflow_run, state:, project:, user:, workflow:, created_at:)
  end

  def call(**opts)
    RecentActivityService.new(@company, **opts).call
  end

  # ─── Aggregation across all three sources ─────────────────────────────────────

  test "aggregates board, session, and workflow activity for the company" do
    create_board_activity(event_type: "task_created")
    create_agent_session(state: "running")
    create_run(state: "completed")

    result = call

    assert_equal 3, result[:total]
    assert_equal 3, result[:activities].size

    event_types = result[:activities].map { |a| a[:event_type] }
    assert_equal %w[session_started task_created workflow_completed], event_types.sort
  end

  test "returns pagination metadata alongside activities" do
    create_board_activity(event_type: "task_created")

    result = call(page: 2, per_page: 20)

    assert_equal 20, result[:per_page]
    assert_equal 2, result[:page]
    assert_equal 1, result[:total]
    assert_equal [], result[:activities]
  end

  test "each activity is a hash with the full item shape" do
    create_board_activity(event_type: "task_created")

    item = call[:activities].first

    assert_equal %i[actor_name actor_type description event_type metadata occurred_at],
                 item.keys.sort
    assert_equal @user.name, item[:actor_name]
    assert_equal "human", item[:actor_type]
  end

  # ─── Board activity descriptions ──────────────────────────────────────────────

  test "board description uses the linked task title" do
    task = create(:board_task, board: @board, board_column: @board_column, title: "Fix login")
    create_board_activity(event_type: "task_created", board_task: task)

    assert_equal 'Task "Fix login" created', call[:activities].first[:description]
  end

  test "board description falls back to metadata task_title then a generic label" do
    create_board_activity(event_type: "task_created", metadata: { "task_title" => "Legacy task" },
                          created_at: 1.minute.ago)
    create_board_activity(event_type: "task_created", created_at: 2.minutes.ago)

    descriptions = call[:activities].map { |a| a[:description] }
    assert_equal [ 'Task "Legacy task" created', 'Task "a task" created' ], descriptions
  end

  test "task_moved description includes the destination column from metadata" do
    task = create(:board_task, board: @board, board_column: @board_column, title: "Ship it")
    create_board_activity(event_type: "task_moved", board_task: task,
                          metadata: { "to_column" => "Done" })

    assert_equal 'Task "Ship it" moved to Done', call[:activities].first[:description]
  end

  test "board activity preserves event type, actor type, and metadata" do
    create_board_activity(event_type: "comment_added", actor_type: "agent",
                          metadata: { "task_title" => "Docs", "note" => "hi" })

    item = call[:activities].first
    assert_equal "comment_added", item[:event_type]
    assert_equal "agent", item[:actor_type]
    assert_equal({ "task_title" => "Docs", "note" => "hi" }, item[:metadata])
    assert_equal 'Comment added on "Docs"', item[:description]
  end

  # ─── Session items ────────────────────────────────────────────────────────────

  test "session state maps to event type and description" do
    create_agent_session(state: "running",  created_at: 1.minute.ago)
    create_agent_session(state: "finished", created_at: 2.minutes.ago)
    create_agent_session(state: "failed",   created_at: 3.minutes.ago)

    activities = call[:activities]
    assert_equal %w[session_started session_completed session_failed],
                 activities.map { |a| a[:event_type] }
    assert_equal "Session started with claude_code",   activities[0][:description]
    assert_equal "Session completed with claude_code", activities[1][:description]
    assert_equal "Session failed with claude_code",    activities[2][:description]
    assert(activities.all? { |a| a[:actor_type] == "human" })
    assert(activities.all? { |a| a[:actor_name] == @user.name })
  end

  test "only agent_session terminal sessions are included" do
    create_agent_session(state: "running")
    create(:terminal_session, :auth_setup, state: "running", user: @user)

    result = call
    assert_equal 1, result[:total]
    assert_equal "session_started", result[:activities].first[:event_type]
  end

  # ─── Workflow run items ───────────────────────────────────────────────────────

  test "workflow run state maps to event type and description" do
    create_run(state: "pending",   created_at: 1.minute.ago)
    create_run(state: "completed", created_at: 2.minutes.ago)
    create_run(state: "cancelled", created_at: 3.minutes.ago)

    activities = call[:activities]
    assert_equal %w[workflow_triggered workflow_completed workflow_cancelled],
                 activities.map { |a| a[:event_type] }
    assert_equal %Q(Workflow "#{@workflow.name}" queued),    activities[0][:description]
    assert_equal %Q(Workflow "#{@workflow.name}" completed), activities[1][:description]
    assert_equal %Q(Workflow "#{@workflow.name}" cancelled), activities[2][:description]
  end

  # ─── Ordering ─────────────────────────────────────────────────────────────────

  test "activities are sorted by occurred_at descending across sources" do
    create_board_activity(event_type: "task_created", created_at: 3.hours.ago)
    create_run(state: "completed", created_at: 2.hours.ago)
    create_agent_session(state: "running", created_at: 1.hour.ago)

    activities = call[:activities]
    assert_equal %w[session_started workflow_completed task_created],
                 activities.map { |a| a[:event_type] }

    occurred_ats = activities.map { |a| a[:occurred_at] }
    assert_equal occurred_ats.sort.reverse, occurred_ats
  end

  # ─── Pagination ───────────────────────────────────────────────────────────────

  test "paginates the combined activity list" do
    3.times { |i| create_board_activity(event_type: "task_created", created_at: i.minutes.ago) }

    page1 = call(page: 1, per_page: 2)
    assert_equal 3, page1[:total]
    assert_equal 2, page1[:activities].size

    page2 = call(page: 2, per_page: 2)
    assert_equal 3, page2[:total]
    assert_equal 1, page2[:activities].size
  end

  test "clamps page and per_page into valid ranges" do
    create_board_activity(event_type: "task_created")

    result = call(page: 0, per_page: 500)
    assert_equal 1, result[:page]
    assert_equal 100, result[:per_page]
  end

  # ─── Scoping ──────────────────────────────────────────────────────────────────

  test "project scope limits results to the given project" do
    other_project = create(:project, company: @company, owner: @user)
    other_board = create(:board, project: other_project)

    create_board_activity(event_type: "task_created", board: @board)
    create_board_activity(event_type: "task_updated", board: other_board)
    create_agent_session(state: "running", project: @project)
    create_agent_session(state: "running", project: other_project)
    create_run(state: "completed", project: @project)
    create_run(state: "completed", project: other_project)

    result = RecentActivityService.new(@company, project: @project).call

    assert_equal 3, result[:total]
    event_types = result[:activities].map { |a| a[:event_type] }.sort
    assert_equal %w[session_started task_created workflow_completed], event_types
  end

  test "company scope excludes activity belonging to other companies" do
    other_company = create(:company)
    other_user = create(:user, :employee, company: other_company)
    other_project = create(:project, company: other_company, owner: other_user)
    other_board = create(:board, project: other_project)

    create_board_activity(event_type: "task_created", board: other_board, actor: other_user)
    create_agent_session(state: "running", user: other_user)
    create_run(state: "completed", project: other_project, user: other_user)

    # In-company activity that SHOULD appear.
    create_board_activity(event_type: "task_created")

    result = call
    assert_equal 1, result[:total]
    assert_equal "task_created", result[:activities].first[:event_type]
  end
end
