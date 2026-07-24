# frozen_string_literal: true

require "test_helper"

class ContextBuilders::AgentRoleTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "applicable returns false without configured agent" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", configured_agent: nil)
    builder = ContextBuilders::AgentRole.new(session)
    assert_not builder.applicable?
  end

  test "applicable returns true with configured agent" do
    agent = Agent.create!(name: "test_agent", title: "Test Agent", persona: "You are helpful.",
      scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", configured_agent: agent)
    builder = ContextBuilders::AgentRole.new(session)
    assert builder.applicable?
  end

  test "build returns section with agent system prompt" do
    agent = Agent.create!(name: "architect", title: "Architect", persona: "Senior architect.",
      communication_style: "Direct", scope: @project)
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", configured_agent: agent)

    sections = ContextBuilders::AgentRole.new(session).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "agent-role", section.tag
    assert_equal :important, section.priority
    assert_equal :top, section.position_hint
    assert_includes section.content, "Architect"
    assert_includes section.content, "Senior architect."
  end
end
