# frozen_string_literal: true

require "test_helper"

class SessionContextConstructorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company, preferred_agent_language: nil)
    @project = create(:project, company: @company, owner: @user)
  end

  test "build returns XML-markdown string for standalone session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "do work")

    output = SessionContextConstructor.build(session)

    assert_includes output, "<critical-rules"
    assert_includes output, "<session-context"
    assert_includes output, "<workspace"
    assert_includes output, "<shell-tools"
    assert_includes output, "<output-rules"
    assert_not_includes output, "<workflow-context"
    assert_not_includes output, "<board-context"
  end

  test "critical-rules appears before output-rules (sandwich pattern)" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "do work")

    output = SessionContextConstructor.build(session)
    critical_pos = output.index("<critical-rules")
    output_pos = output.index("<output-rules")

    assert_not_nil critical_pos
    assert_not_nil output_pos
    assert critical_pos < output_pos, "critical-rules must appear before output-rules"
  end

  test "build_result returns ContextResult" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    result = SessionContextConstructor.build_result(session)
    assert_kind_of ContextResult, result
    assert result.render.is_a?(String)
    assert result.applied_builders.is_a?(Array)
    assert result.skipped_builders.is_a?(Array)
    assert result.build_time_ms > 0
  end

  test "skipped builders tracked when agent not configured" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", configured_agent: nil)

    result = SessionContextConstructor.build_result(session)
    assert_includes result.skipped_builders, "agent_role"
    assert_includes result.skipped_builders, "resources"
    assert_not_includes result.applied_builders, "agent_role"
  end

  test "applied builders tracked" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive")

    result = SessionContextConstructor.build_result(session)
    assert_includes result.applied_builders, "session_info"
    assert_includes result.applied_builders, "workspace"
    assert_includes result.applied_builders, "tools"
    assert_includes result.applied_builders, "output_rules"
  end

  test "BUILDERS constant is frozen" do
    assert SessionContextConstructor::BUILDERS.frozen?
  end
end
