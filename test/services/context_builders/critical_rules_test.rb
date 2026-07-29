# frozen_string_literal: true

require "test_helper"

class ContextBuilders::CriticalRulesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company, preferred_agent_language: nil)
    @project = create(:project, company: @company, owner: @user)
  end

  test "non_interactive mode with language produces critical-rules section" do
    @user.company_memberships.sole.update_column(:preferred_agent_language, "ru")
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")

    builder = ContextBuilders::CriticalRules.new(session.reload)
    sections = builder.build

    assert_equal 1, sections.length
    section = sections.first
    assert_equal "critical-rules", section.tag
    assert_equal :critical, section.priority
    assert_equal :top, section.position_hint
    assert_equal "critical_rules", section.builder_name
    assert_includes section.content, "NEVER ask questions"
    assert_includes section.content, "**Communication Language:** ru"
  end

  test "interactive mode without language returns empty array" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "interactive")

    builder = ContextBuilders::CriticalRules.new(session)
    sections = builder.build

    assert_equal [], sections
  end

  test "interactive mode with language produces language-only section" do
    @user.company_memberships.sole.update_column(:preferred_agent_language, "en")
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "interactive")

    builder = ContextBuilders::CriticalRules.new(session.reload)
    sections = builder.build

    assert_equal 1, sections.length
    assert_includes sections.first.content, "**Communication Language:** en"
    assert_not_includes sections.first.content, "NEVER ask questions"
  end

  test "non_interactive rules include key backward-compatible phrases" do
    session = create(:terminal_session, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")

    builder = ContextBuilders::CriticalRules.new(session)
    sections = builder.build
    content = sections.first.content

    assert_includes content, "NEVER ask questions"
    assert_includes content, "NEVER present options"
    assert_includes content, "`/workspace/outputs/`"
    assert_includes content, "actionable artifacts"
  end
end
