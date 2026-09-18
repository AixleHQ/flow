# frozen_string_literal: true

require "test_helper"

class AuthSessionTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, company: create(:company))
  end

  test "find_live_by_token matches on the digest, never the raw token" do
    token = "as_#{SecureRandom.hex(8)}"
    auth_session = create(:auth_session, user: @user, token_digest: AuthSession.digest(token))

    assert_equal auth_session, AuthSession.find_live_by_token(token)
    assert_nil AuthSession.find_live_by_token("as_wrong")
    assert_nil AuthSession.find_live_by_token(nil)
  end

  test "a revoked session is no longer live" do
    auth_session = create(:auth_session, user: @user)

    auth_session.revoke!

    assert auth_session.revoked?
    refute_includes AuthSession.live, auth_session
  end

  test "revoking twice keeps the original moment" do
    auth_session = create(:auth_session, user: @user)
    auth_session.revoke!
    first_revoked_at = auth_session.revoked_at

    auth_session.revoke!

    assert_equal first_revoked_at, auth_session.reload.revoked_at
  end

  test "deleting a user takes their sessions and proofs" do
    started = Auth::SessionService.start(user: @user, provider: IdentityProvider.password)

    assert_difference "AuthSessionProof.count", -1 do
      assert_difference "AuthSession.count", -1 do
        started.auth_session.user.destroy!
      end
    end
  end
end
