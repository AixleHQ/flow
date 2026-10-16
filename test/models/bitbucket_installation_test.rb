# frozen_string_literal: true

require "test_helper"

class BitbucketInstallationTest < ActiveSupport::TestCase
  setup do
    @installation = create(:bitbucket_installation)
  end

  test "keeps the token that lives longer, whichever arrives last" do
    assert @installation.store_token!("fresh", expires_at: 3.hours.from_now)
    assert_not @installation.store_token!("older", expires_at: 1.hour.from_now)

    assert_equal "fresh", @installation.usable_token(min_remaining: 60)
  end

  test "a delivery that brings no usable token still counts as hearing from the app" do
    @installation.update_columns(last_invocation_at: 1.hour.ago)

    assert_not @installation.store_token!(nil, expires_at: nil)

    assert_in_delta Time.current, @installation.reload.last_invocation_at, 5
  end

  test "an already expired token is never stored" do
    assert_not @installation.store_token!("stale", expires_at: 1.minute.ago)

    assert_nil @installation.reload.token_expires_at
  end

  test "a token too close to expiry is not handed out" do
    @installation.store_token!("short", expires_at: 2.minutes.from_now)

    assert_nil @installation.usable_token(min_remaining: 300)
    assert_equal "short", @installation.usable_token(min_remaining: 60)
  end

  test "an entry no key can read is a miss" do
    @installation.update_columns(encrypted_access_token: "not-a-ciphertext", token_expires_at: 2.hours.from_now)

    assert_nil @installation.reload.usable_token(min_remaining: 60)
  end

  test "the workspace and installation identity cannot change" do
    @installation.workspace_uuid = "{other}"

    assert_not @installation.valid?
    assert_includes @installation.errors[:workspace_uuid], "cannot change on an existing installation"
  end
end
