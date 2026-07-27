# frozen_string_literal: true

require "test_helper"

class ContextBuilders::WorkflowContextTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project, name: "Product Planning", description: "End-to-end product planning workflow")

    @step1 = create(:step, workflow: @workflow, name: "Analyze", position: 1, instructions: "Run code analysis tools")
    @step2 = create(:step, workflow: @workflow, name: "Implement", position: 2, instructions: "Write the code")
    @step3 = create(:step, workflow: @workflow, name: "Review", position: 3, instructions: "Check results")

    @workflow_run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, mode: "non_interactive")
    @step_run = create(:step_run, :running, workflow_run: @workflow_run, step: @step2)
  end

  # -- AC #1: applicable? returns true for workflow step session --

  test "applicable? returns true when session has step_run" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    assert builder.applicable?
  end

  # -- AC #2: applicable? returns false for standalone session --

  test "applicable? returns false for standalone session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    builder = ContextBuilders::WorkflowContext.new(session)
    assert_not builder.applicable?
  end

  # -- AC #3: workflow-context section --

  test "build produces workflow-context section with correct tag, priority, position" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    overview = sections.find { |s| s.tag == "workflow-context" }
    assert_not_nil overview
    assert_equal :important, overview.priority
    assert_equal :top, overview.position_hint
    assert_equal "workflow_context", overview.builder_name
  end

  test "workflow-context content includes workflow name, mode, and step position" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    content = sections.find { |s| s.tag == "workflow-context" }.content
    assert_includes content, "Product Planning"
    assert_includes content, "non_interactive"
    assert_includes content, @workflow_run.id.to_s
    assert_includes content, "Step 2 of 3"
  end

  # -- AC #4: current-step section --

  test "build produces current-step section with critical priority" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    step_section = sections.find { |s| s.tag == "current-step" }
    assert_not_nil step_section
    assert_equal :critical, step_section.priority
    assert_equal :middle, step_section.position_hint
  end

  test "current-step content includes step name and instructions" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    content = sections.find { |s| s.tag == "current-step" }.content
    assert_includes content, "Implement"
    assert_includes content, "Write the code"
  end

  test "build returns exactly 2 sections for step without sub-steps" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build
    assert_equal 2, sections.length
    assert_equal %w[workflow-context current-step], sections.map(&:tag)
  end

  # -- Story 26.2: Sub-Steps Checklist --

  test "sub-steps section produced when step has sub-steps" do
    ss1 = create(:sub_step, step: @step2, name: "Analyze code", position: 1)
    ss2 = create(:sub_step, step: @step2, name: "Write tests", position: 2)
    ss3 = create(:sub_step, step: @step2, name: "Implement", position: 3)

    ssr1 = create(:sub_step_run, :completed, step_run: @step_run, sub_step: ss1)
    ssr2 = create(:sub_step_run, :in_progress, step_run: @step_run, sub_step: ss2)
    create(:sub_step_run, step_run: @step_run, sub_step: ss3)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    sub_section = sections.find { |s| s.tag == "sub-steps" }
    assert_not_nil sub_section
    assert_equal :important, sub_section.priority
    assert_equal :middle, sub_section.position_hint
  end

  test "sub-steps section includes status icons for all states" do
    ss1 = create(:sub_step, step: @step2, name: "Done step", position: 1)
    ss2 = create(:sub_step, step: @step2, name: "Active step", position: 2)
    ss3 = create(:sub_step, step: @step2, name: "Skipped step", position: 3)
    ss4 = create(:sub_step, step: @step2, name: "Pending step", position: 4)

    create(:sub_step_run, :completed, step_run: @step_run, sub_step: ss1)
    create(:sub_step_run, :in_progress, step_run: @step_run, sub_step: ss2)
    create(:sub_step_run, step_run: @step_run, sub_step: ss3, state: "skipped")
    create(:sub_step_run, step_run: @step_run, sub_step: ss4)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "sub-steps" }.content

    assert_includes content, "✅"
    assert_includes content, "🔄"
    assert_includes content, "⏭️"
    assert_includes content, "⬜"
  end

  test "sub-steps section includes note and data truncated" do
    ss1 = create(:sub_step, step: @step2, name: "Analysis", position: 1)
    ssr = create(:sub_step_run, :completed, step_run: @step_run, sub_step: ss1,
      note: "Analyzed codebase " + "x" * 250,
      data: { "files" => 12, "issues" => 3 })

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "sub-steps" }.content

    assert_includes content, "→ Analyzed codebase"
    assert_includes content, "→ data:"
    assert_includes content, '"files"'
  end

  test "sub-steps section includes mark_sub_step instructions" do
    create(:sub_step, step: @step2, name: "Test step", position: 1)
    create(:sub_step_run, step_run: @step_run, sub_step: @step2.sub_steps.first)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "sub-steps" }.content

    assert_includes content, "mark_sub_step"
    assert_includes content, "in_progress"
    assert_includes content, "completed"
  end

  test "no sub-steps section when step has no sub-steps" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    assert_nil sections.find { |s| s.tag == "sub-steps" }
  end

  # -- Story 26.3: Previous Steps Summary --

  test "previous-steps section produced when earlier steps completed" do
    step_run1 = create(:step_run, :completed, workflow_run: @workflow_run, step: @step1, step_note: "Analyzed the code thoroughly")

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    prev_section = sections.find { |s| s.tag == "previous-steps" }
    assert_not_nil prev_section
    assert_equal :info, prev_section.priority
    assert_equal :middle, prev_section.position_hint
  end

  test "previous-steps content includes step name, icon, and note" do
    create(:step_run, :completed, workflow_run: @workflow_run, step: @step1, step_note: "Found 15 issues in codebase")

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "previous-steps" }.content

    assert_includes content, "Analyze"
    assert_includes content, "✅"
    assert_includes content, "Found 15 issues"
  end

  test "previous-steps shows skipped icon for skipped steps" do
    create(:step_run, :skipped, workflow_run: @workflow_run, step: @step1)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "previous-steps" }.content

    assert_includes content, "⏭️"
    assert_includes content, "skipped"
  end

  test "previous-steps truncates step note to 500 chars" do
    long_note = "A" * 600
    create(:step_run, :completed, workflow_run: @workflow_run, step: @step1, step_note: long_note)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "previous-steps" }.content

    assert_includes content, "A" * 497 + "..."
    assert_not content.include?("A" * 600)
  end

  test "previous-steps includes completed sub-step names with notes" do
    ss = create(:sub_step, step: @step1, name: "Pre-analysis", position: 1)
    sr1 = create(:step_run, :completed, workflow_run: @workflow_run, step: @step1)
    create(:sub_step_run, :completed, step_run: sr1, sub_step: ss, note: "Sub-step done well")

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "previous-steps" }.content

    assert_includes content, "Pre-analysis"
    assert_includes content, "Sub-step done well"
  end

  test "no previous-steps section on first step" do
    first_step_run = create(:step_run, :running, workflow_run: @workflow_run, step: @step1)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: first_step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    assert_nil sections.find { |s| s.tag == "previous-steps" }
  end

  # -- Story 26.4: Workflow Tools Section --

  test "workflow-tools section produced when step has sub-steps" do
    create(:sub_step, step: @step2, name: "Task A", position: 1)
    create(:sub_step_run, step_run: @step_run, sub_step: @step2.sub_steps.first)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    tools_section = sections.find { |s| s.tag == "workflow-tools" }
    assert_not_nil tools_section
    assert_equal :important, tools_section.priority
  end

  test "workflow-tools content includes tool names" do
    create(:sub_step, step: @step2, name: "Task A", position: 1)
    create(:sub_step_run, step_run: @step_run, sub_step: @step2.sub_steps.first)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "workflow-tools" }.content

    assert_includes content, "list_sub_steps"
    assert_includes content, "mark_sub_step"
  end

  test "workflow-tools content includes key parameters" do
    create(:sub_step, step: @step2, name: "Task A", position: 1)
    create(:sub_step_run, step_run: @step_run, sub_step: @step2.sub_steps.first)

    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    content = builder.build.find { |s| s.tag == "workflow-tools" }.content

    assert_includes content, "in_progress"
    assert_includes content, "completed"
    assert_includes content, "skipped"
    assert_includes content, "note"
  end

  test "no workflow-tools section when no sub-steps" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: @step_run)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    assert_nil sections.find { |s| s.tag == "workflow-tools" }
  end

  # -- AC #5: BUILDERS registration --

  test "WorkflowContext is registered in BUILDERS after Workspace and before Tools" do
    builders = SessionContextConstructor::BUILDERS
    workspace_idx = builders.index(ContextBuilders::Workspace)
    wf_ctx_idx = builders.index(ContextBuilders::WorkflowContext)
    tools_idx = builders.index(ContextBuilders::Tools)

    assert_not_nil wf_ctx_idx, "WorkflowContext must be in BUILDERS"
    assert_operator wf_ctx_idx, :>, workspace_idx, "WorkflowContext must be after Workspace"
    assert_operator wf_ctx_idx, :<, tools_idx, "WorkflowContext must be before Tools"
  end
end
