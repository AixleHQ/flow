# frozen_string_literal: true

require "test_helper"

class AgentCredentialResourceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
  end

  # expires_at is normally derived from the token blob via a before_save; set it
  # directly (bypassing the callback) to exercise each status branch.
  def status_for(expires_at)
    cred = create(:agent_credential, :codex, user: @user,
                  config_data: { "tokens" => { "access_token" => "x" } })
    cred.update_column(:expires_at, expires_at)
    AgentCredentialResource.new(cred.reload).to_h["connectionStatus"]
  end

  test "connection_status is active when the token expiry is far off" do
    assert_equal "active", status_for(2.hours.from_now)
  end

  test "connection_status is active when the token carries no expiry" do
    assert_equal "active", status_for(nil)
  end

  test "connection_status is expiring within 30 minutes of expiry" do
    assert_equal "expiring", status_for(10.minutes.from_now)
  end

  test "connection_status is expired once the token expiry has passed" do
    assert_equal "expired", status_for(1.minute.ago)
  end

  # == how much warning "expiring" gives ==
  #
  # A fixed window was right for an 8-hour token and useless for a 60-day one: a badge
  # that turns amber half an hour before a two-month credential dies tells nobody
  # anything. The window is a tenth of the runtime's declared life, floored at 30 minutes.

  # A credential is unique per (user, company, agent_type), so each runtime gets one row
  # and the expiry is moved under it.
  def status_at(credential, expires_at)
    credential.update_column(:expires_at, expires_at)
    AgentCredentialResource.new(credential.reload).to_h["connectionStatus"]
  end

  test "a long-lived token warns days ahead, not minutes" do
    cursor = create(:agent_credential, :cursor_cli, user: @user,
                    config_data: { "accessToken" => "opaque", "refreshToken" => "r" })

    assert_equal "expiring", status_at(cursor, 3.days.from_now)
    assert_equal "active", status_at(cursor, 30.days.from_now)
  end

  test "a short-lived token keeps the floor rather than a shorter window" do
    # 8 hours nominal would give 48 minutes; the floor only ever raises it.
    claude = create(:agent_credential, :claude_code, user: @user,
                    config_data: { "claudeAiOauth" => { "accessToken" => "t", "expiresAt" => 1 } })

    assert_equal "expiring", status_at(claude, 40.minutes.from_now)
    assert_equal "active", status_at(claude, 3.hours.from_now)
  end

  test "a runtime that declares no lifetime keeps the 30-minute floor" do
    codex = create(:agent_credential, :codex, user: @user,
                   config_data: { "tokens" => { "access_token" => "x" } })

    assert_equal "expiring", status_at(codex, 20.minutes.from_now)
    assert_equal "active", status_at(codex, 90.minutes.from_now)
  end
end
