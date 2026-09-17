# frozen_string_literal: true

require "test_helper"

class AgentCredentialMailerTest < ActionMailer::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  test "refresh_failed tells the owner which agent to sign in to, and why" do
    credential = create(:agent_credential, :errored, user: @user, agent_type: "claude_code")

    mail = AgentCredentialMailer.refresh_failed(credential)

    assert_equal [ @user.email ], mail.to
    assert_match(/sign in to Claude Code again/i, mail.subject)
    assert_match "invalid_grant", mail.body.encoded
    assert_match "/profile", mail.body.encoded
  end

  test "refresh_failed renders without a recorded reason" do
    credential = create(:agent_credential, user: @user, agent_type: "codex", status: "error")

    mail = AgentCredentialMailer.refresh_failed(credential)

    assert_match(/Codex/, mail.body.encoded)
  end
end
