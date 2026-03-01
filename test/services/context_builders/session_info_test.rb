# frozen_string_literal: true

require "test_helper"

class ContextBuilders::SessionInfoTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "build returns session-context section with session details" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project,
      mode: "interactive", agent_type: "claude_code")

    sections = ContextBuilders::SessionInfo.new(session).build
    assert_equal 1, sections.length

    section = sections.first
    assert_equal "session-context", section.tag
    assert_equal :info, section.priority
    assert_includes section.content, session.id.to_s
    assert_includes section.content, "claude_code"
    assert_includes section.content, "interactive"
    assert_includes section.content, @project.name
  end
end
