# frozen_string_literal: true

require "test_helper"

class SessionToolTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, user: @user, project: @project)
    @tool = create(:tool, scope: @company)
  end

  test "can associate tool with session" do
    session_tool = SessionTool.create!(
      terminal_session: @session,
      tool: @tool
    )

    assert session_tool.persisted?
    assert_includes @session.reload.tools, @tool
  end

  test "prevents duplicate tool assignment" do
    SessionTool.create!(terminal_session: @session, tool: @tool)

    assert_raises(ActiveRecord::RecordInvalid) do
      SessionTool.create!(terminal_session: @session, tool: @tool)
    end
  end

  test "destroying session destroys session_tools" do
    SessionTool.create!(terminal_session: @session, tool: @tool)
    assert_equal 1, SessionTool.count

    @session.destroy

    assert_equal 0, SessionTool.count
  end
end
