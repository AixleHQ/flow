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
end
