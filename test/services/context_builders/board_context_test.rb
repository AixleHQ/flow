# frozen_string_literal: true

require "test_helper"

class ContextBuilders::BoardContextTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, name: "Sprint Board", project: @project)
    @column = create(:board_column, name: "In Progress", board: @board)
    @workflow = create(:workflow, scope: @company, name: "Dev Workflow")
    @step = create(:step, workflow: @workflow, name: "Implement", position: 1)
  end

  # -- AC #1: applicable? returns true when board_task present --

  test "applicable? returns true when workflow_run has board_task" do
    task = create(:board_task, board: @board, board_column: @column, title: "Fix auth bug")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    builder = ContextBuilders::BoardContext.new(session)
    assert builder.applicable?
  end

  # -- AC #2: applicable? returns false for standalone session --

  test "applicable? returns false for standalone session without step_run" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    builder = ContextBuilders::BoardContext.new(session)
    assert_not builder.applicable?
  end

  # -- AC #3: applicable? returns false for workflow without board_task --

  test "applicable? returns false when workflow_run has no board_task" do
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    builder = ContextBuilders::BoardContext.new(session)
    assert_not builder.applicable?
  end

  # -- AC #4: board-context section with correct tag, priority, position --

  test "build produces board-context section with correct tag, priority, and position" do
    task = create(:board_task, board: @board, board_column: @column, title: "Implement feature")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    sections = ContextBuilders::BoardContext.new(session).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "board-context", section.tag
    assert_equal :important, section.priority
    assert_equal :top, section.position_hint
    assert_equal "board_context", section.builder_name
  end

  # -- AC #4: content includes board name, task title, column, priority, description, tags --

  test "content includes board name, task title with id, and column name" do
    task = create(:board_task, board: @board, board_column: @column, title: "Fix login flow")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content

    assert_includes content, "Sprint Board"
    assert_includes content, "Fix login flow"
    assert_includes content, task.id.to_s
    assert_includes content, "In Progress"
  end

  test "content includes priority when present" do
    task = create(:board_task, board: @board, board_column: @column, title: "Critical bug", priority: :high)
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "high"
  end

  test "content omits priority when not set" do
    task = create(:board_task, board: @board, board_column: @column, title: "No priority task")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_not_includes content, "Priority"
  end

  test "content includes description truncated to 500 chars" do
    long_desc = "A" * 600
    task = create(:board_task, board: @board, board_column: @column, title: "Desc task", description: long_desc)
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "A" * 497 + "..."
    assert_not_includes content, "A" * 600
  end

  test "content includes tags when present" do
    task = create(:board_task, board: @board, board_column: @column, title: "Tagged task", tags: %w[backend auth urgent])
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "backend, auth, urgent"
  end

  test "content includes board MCP tools instruction" do
    task = create(:board_task, board: @board, board_column: @column, title: "Any task")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "board_get_task"
    assert_includes content, "board_add_comment"
    assert_includes content, "board_move_task"
  end

  # -- Story 27.2: Recent Comments in Board Context --

  # -- AC 27.2#1: Recent comments included (up to 5) --

  test "content includes recent comments when present" do
    task = create(:board_task, board: @board, board_column: @column, title: "Commented task")
    create(:task_comment, board_task: task, body: "First comment", author: @user)
    create(:task_comment, board_task: task, body: "Second comment", author: @user)

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "Recent Comments"
    assert_includes content, "First comment"
    assert_includes content, "Second comment"
  end

  test "at most 5 comments shown" do
    task = create(:board_task, board: @board, board_column: @column, title: "Many comments task")
    7.times { |i| create(:task_comment, board_task: task, body: "Comment #{i}", author: @user, created_at: i.hours.ago) }

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    comment_lines = content.lines.select { |l| l.match?(/\*\*#{Regexp.escape(@user.name)}\*\*/) }
    assert_equal 5, comment_lines.length
  end

  # -- AC 27.2#2: Comment details with author name and truncated body --

  test "comment body truncated to 200 chars" do
    task = create(:board_task, board: @board, board_column: @column, title: "Long comment task")
    long_body = "B" * 300
    create(:task_comment, board_task: task, body: long_body, author: @user)

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "B" * 197 + "..."
    assert_not_includes content, "B" * 300
  end

  test "comment includes author name" do
    task = create(:board_task, board: @board, board_column: @column, title: "Author test")
    create(:task_comment, board_task: task, body: "Hello world", author: @user)

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, @user.name
  end

  # -- AC 27.2#3: No comments subsection when empty --

  test "no Recent Comments subsection when task has no comments" do
    task = create(:board_task, board: @board, board_column: @column, title: "No comments task")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_not_includes content, "Recent Comments"
  end

  # -- AC #5: BUILDERS registration position --

  test "BoardContext is in BUILDERS after WorkflowContext and before Tools" do
    builders = SessionContextConstructor::BUILDERS
    wf_idx = builders.index(ContextBuilders::WorkflowContext)
    bc_idx = builders.index(ContextBuilders::BoardContext)
    tools_idx = builders.index(ContextBuilders::Tools)

    assert_not_nil bc_idx, "BoardContext must be in BUILDERS"
    assert bc_idx > wf_idx, "BoardContext must be after WorkflowContext"
    assert bc_idx < tools_idx, "BoardContext must be before Tools"
  end
end
