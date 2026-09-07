# frozen_string_literal: true

require "test_helper"

class ContextBuilders::SessionCompletionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company, preferred_agent_language: nil)
    @project = create(:project, company: @company, owner: @user)
  end

  test "non_interactive session gets a critical bottom section naming both tools" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")

    sections = ContextBuilders::SessionCompletion.new(session).build

    assert_equal 1, sections.length
    section = sections.first
    assert_equal "session-completion", section.tag
    assert_equal :critical, section.priority
    assert_equal :footer, section.position_hint
    assert_equal "session_completion", section.builder_name
    assert_includes section.content, "`finish_session`"
    assert_includes section.content, "`fail_session`"
  end

  test "the mandate spells out what skipping the call costs" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")

    content = ContextBuilders::SessionCompletion.new(session).build.first.content

    assert_includes content, "does NOT end when you stop writing"
    assert_includes content, "sweeper"
    assert_includes content, "Partial work is a `fail_session`"
  end

  test "interactive session is not applicable" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "interactive")

    assert_not ContextBuilders::SessionCompletion.new(session).applicable?
  end

  test "constructor renders the mandate as the last section of a non_interactive context" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")

    rendered = SessionContextConstructor.build(session)

    assert_includes rendered, "<session-completion priority=\"critical\">"
    assert_equal "</session-completion>", rendered.lines.map(&:strip).reject(&:empty?).last
  end

  test "interactive context carries no session-completion section" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "interactive")

    result = SessionContextConstructor.build_result(session)

    assert_not_includes result.sections.map(&:tag), "session-completion"
    assert_includes result.skipped_builders, "session_completion"
  end
end
