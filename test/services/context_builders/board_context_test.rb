# frozen_string_literal: true

require "test_helper"

class ContextBuilders::BoardContextTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, name: "Sprint Board", project: @project)
    @column = create(:board_column, name: "In Progress", board: @board)
    @workflow = create(:workflow, scope: @project, name: "Dev Workflow")
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

  # -- AC #4: content includes board name, task title, column, priority, tags --

  test "content includes board name, task title with id, and column name" do
    task = create(:board_task, board: @board, board_column: @column, title: "Fix login flow")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content

    assert_includes content, "Sprint Board"
    assert_includes content, "Fix login flow"
    assert_includes content, "##{task.number} Fix login flow (id: #{task.id})"
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

  test "content includes tags when present" do
    task = create(:board_task, board: @board, board_column: @column, title: "Tagged task", tags: %w[backend auth urgent])
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "backend, auth, urgent"
  end

  test "content includes board columns with current marker" do
    create(:board_column, name: "Done", board: @board, position: 2)
    task = create(:board_task, board: @board, board_column: @column, title: "Columns task")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "Board Columns"
    assert_includes content, "In Progress"
    assert_includes content, "← current"
    assert_includes content, "Done"
  end

  test "no automatic task completion rule in context" do
    create(:board_column, name: "QA", board: @board, position: 2)
    task = create(:board_task, board: @board, board_column: @column, title: "Move task")
    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_not_includes content, "Task Completion Rule"
  end

  test "a short description is shown whole and comments are left to their tool" do
    task = create(:board_task, board: @board, board_column: @column, title: "Short task",
      description: "Rename the settings tab to Billing")
    create(:task_comment, board_task: task, body: "Reviewed: needs a migration", author: @user)

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_includes content, "- **Description:** Rename the settings tab to Billing"
    assert_not_includes content, "Reviewed: needs a migration"
    assert_includes content, "`board_list_comments`"
    assert_includes content, "`board_get_comment`"
    assert_not_includes content, "`board_get_task`"
  end

  test "a description over the inline limit is replaced by a pointer, never truncated" do
    long_spec = "Acceptance criteria. " * 100
    task = create(:board_task, board: @board, board_column: @column, title: "Spec task", description: long_spec)

    workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: task)
    step_run = create(:step_run, :running, workflow_run: workflow_run, step: @step)
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)

    content = ContextBuilders::BoardContext.new(session).build.first.content
    assert_operator long_spec.length, :>, ContextBuilders::BoardContext::DESCRIPTION_INLINE_LIMIT
    assert_not_includes content, "Acceptance criteria."
    assert_includes content, "`board_get_task`"
    assert_includes content, "`board_list_comments`"
  end

  # -- AC #5: BUILDERS registration position --

  test "BoardContext is in BUILDERS after WorkflowContext and before Tools" do
    builders = SessionContextConstructor::BUILDERS
    wf_idx = builders.index(ContextBuilders::WorkflowContext)
    bc_idx = builders.index(ContextBuilders::BoardContext)
    tools_idx = builders.index(ContextBuilders::Tools)

    assert_not_nil bc_idx, "BoardContext must be in BUILDERS"
    assert_operator bc_idx, :>, wf_idx, "BoardContext must be after WorkflowContext"
    assert_operator bc_idx, :<, tools_idx, "BoardContext must be before Tools"
  end
end
