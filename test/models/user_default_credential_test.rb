# frozen_string_literal: true

require "test_helper"

class UserDefaultCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  test "default_agent_runtime returns agent_type of default credential" do
    credential = create(:agent_credential, user: @user, agent_type: "gemini_cli")
    @user.reload

    assert_equal "gemini_cli", @user.default_agent_runtime
  end

  test "default_agent_runtime returns nil when no default" do
    assert_nil @user.default_agent_runtime
  end

  test "validation rejects credential not belonging to user" do
    other_user = create(:user, company: @company)
    other_cred = create(:agent_credential, user: other_user, agent_type: "claude_code")

    @user.default_agent_credential_id = other_cred.id
    assert_not @user.valid?
    assert_includes @user.errors[:default_agent_credential_id], "must belong to this user"
  end

  test "validation accepts nil default_agent_credential_id" do
    @user.default_agent_credential_id = nil
    assert @user.valid?
  end

  test "validation accepts own credential" do
    credential = create(:agent_credential, user: @user, agent_type: "claude_code")
    @user.reload

    assert_equal credential.id, @user.default_agent_credential_id
    assert @user.valid?
  end
end
