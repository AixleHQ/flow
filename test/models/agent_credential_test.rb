# frozen_string_literal: true

require "test_helper"

class AgentCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  # --- Auto-set default on creation ---

  test "first credential sets user default_agent_credential" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")

    @user.reload
    assert_equal credential.id, @user.default_agent_credential_id
  end

  test "subsequent credential updates user default_agent_credential" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")

    @user.reload
    assert_equal second.id, @user.default_agent_credential_id
  end

  # --- Reassign on deletion ---

  test "deleting default credential falls back to most recent remaining" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @user.reload.default_agent_credential_id

    second.destroy!

    @user.reload
    assert_equal first.id, @user.default_agent_credential_id
  end

  test "deleting last credential sets default to nil" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")
    assert_equal credential.id, @user.reload.default_agent_credential_id

    credential.destroy!

    @user.reload
    assert_nil @user.default_agent_credential_id
  end

  test "deleting non-default credential does not change default" do
    first = create(:agent_credential, user: @user, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    assert_equal second.id, @user.reload.default_agent_credential_id

    first.destroy!

    @user.reload
    assert_equal second.id, @user.default_agent_credential_id
  end
end
