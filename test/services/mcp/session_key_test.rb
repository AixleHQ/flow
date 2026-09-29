# frozen_string_literal: true

require "test_helper"

class MCP::SessionKeyTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)
    @session = create(:terminal_session, :agent_session, user: user, project: project)
  end

  test "a key resolves back to the session it was minted for" do
    assert_equal @session, MCP::SessionKey.session_for(MCP::SessionKey.generate(@session))
  end

  test "a key with a wrong mac, a bare id, or garbage resolves to nothing" do
    assert_nil MCP::SessionKey.session_for("#{@session.id}.#{'0' * 64}")
    assert_nil MCP::SessionKey.session_for(@session.id.to_s)
    assert_nil MCP::SessionKey.session_for("not-a-key")
    assert_nil MCP::SessionKey.session_for(nil)
  end

  test "the key is not one of the session's other credentials" do
    key = MCP::SessionKey.generate(@session)

    assert_not_equal CloudAuth::SessionKey.generate(@session), key.split(".", 2).last
    assert_not_equal Agents::SessionKey.generate(@session), key.split(".", 2).last
  end

  test "a session keeps the key it holds, and new ones are handed the derived key" do
    assert_equal MCP::SessionKey.generate(@session), @session.reload.mcp_key

    @session.update_column(:mcp_key, "legacy-random-key")
    assert_equal "legacy-random-key", @session.reload.mcp_key
  end
end
