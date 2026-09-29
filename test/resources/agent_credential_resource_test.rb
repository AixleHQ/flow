# frozen_string_literal: true

require "test_helper"

class AgentCredentialResourceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
  end

  # The login's expiry is normally derived from the token blob via a before_save; set it
  # directly (bypassing the callback) to exercise each status branch.
  def status_for(expires_at)
    cred = create(:agent_credential, :codex, user: @user,
                  config_data: { "tokens" => { "access_token" => "x" } })
    cred.update_columns(expires_at: expires_at, metadata: cred.metadata.merge("login_expires_at" => expires_at&.iso8601))
    AgentCredentialResource.new(cred.reload).to_h["connectionStatus"]
  end

  # expires_at is the soonest across every block — when the sweep must wake. A design token
  # that expires first used to turn a working Claude login "Expiring" on the profile.
  test "connection_status and the shown expiry follow the base login, not an add-on" do
    base_exp = 6.hours.from_now
    cred = create(:agent_credential, :claude_code, user: @user, config_data: {
      "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-x", "expiresAt" => (base_exp.to_f * 1000).to_i },
      "designOauth" => { "accessToken" => "sk-ant-design", "expiresAt" => (5.minutes.from_now.to_f * 1000).to_i }
    })

    json = AgentCredentialResource.new(cred.reload).to_h

    assert_equal "active", json["connectionStatus"]
    assert_in_delta base_exp.to_i, Time.zone.parse(json["loginExpiresAt"]).to_i, 2
    assert_operator cred.expires_at, :<, 10.minutes.from_now, "the sweep still wakes for the design token"
  end

  test "a row written before the login expiry was recorded keeps showing the column" do
    cred = create(:agent_credential, :codex, user: @user, config_data: { "tokens" => { "access_token" => "x" } })
    cred.update_columns(expires_at: 10.minutes.from_now, metadata: cred.metadata.except("login_expires_at"))

    assert_equal "expiring", AgentCredentialResource.new(cred.reload).to_h["connectionStatus"]
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
    credential.update_columns(expires_at: expires_at,
                              metadata: credential.metadata.merge("login_expires_at" => expires_at.iso8601))
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
