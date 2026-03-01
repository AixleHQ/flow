# frozen_string_literal: true

require "test_helper"

class ContextBuilders::OutputRulesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "produces output-rules section with critical priority and bottom position" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    sections = ContextBuilders::OutputRules.new(session).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "output-rules", section.tag
    assert_equal :critical, section.priority
    assert_equal :bottom, section.position_hint
  end

  test "content includes standard output rules" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    sections = ContextBuilders::OutputRules.new(session).build
    content = sections.first.content

    assert_includes content, "/workspace/outputs/"
    assert_includes content, "READ-ONLY"
    assert_includes content, "MCP servers"
    assert_includes content, "clean, production-quality"
  end

  test "includes workflow termination warning for workflow step session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    mock_step_run = Object.new
    session.stubs(:step_run).returns(mock_step_run)

    sections = ContextBuilders::OutputRules.new(session).build
    assert_includes sections.first.content, "Marking the last sub-step"
    assert_includes sections.first.content, "session termination"
  end

  test "excludes workflow termination warning for standalone session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    sections = ContextBuilders::OutputRules.new(session).build
    assert_not_includes sections.first.content, "session termination"
  end

  test "sandwich pattern: CriticalRules at top and OutputRules at bottom" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "do work")

    critical = ContextBuilders::CriticalRules.new(session).build
    output = ContextBuilders::OutputRules.new(session).build
    all_sections = critical + output

    rendered = ContextRenderer.render(all_sections)
    critical_pos = rendered.index("<critical-rules")
    output_pos = rendered.index("<output-rules")

    assert critical_pos < output_pos, "critical-rules must appear before output-rules"
  end
end
