# frozen_string_literal: true

require "test_helper"

module Auth
  class SessionServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @password = IdentityProvider.password
      @google = IdentityProvider.deployment!("google")
    end

    test "start mints a session, its first proof, and a token that finds it" do
      started = Auth::SessionService.start(user: @user, provider: @password, ip: "10.0.0.1")

      assert_equal @user, started.auth_session.user
      assert_equal "10.0.0.1", started.auth_session.ip
      assert_equal [ @password.id ], started.auth_session.proved_provider_ids
      assert_equal started.auth_session, AuthSession.find_live_by_token(started.token)
    end

    test "the raw token is never stored" do
      started = Auth::SessionService.start(user: @user, provider: @password)

      refute_equal started.token, started.auth_session.token_digest
      assert_equal AuthSession.digest(started.token), started.auth_session.token_digest
    end

    test "proofs append: a second method never invalidates the first" do
      started = Auth::SessionService.start(user: @user, provider: @password)
      Auth::SessionService.append_proof(started.auth_session, @google)

      assert_equal [ @password.id, @google.id ].sort,
                   started.auth_session.reload.proved_provider_ids.sort
    end

    test "proving the same method twice does not duplicate the proof" do
      started = Auth::SessionService.start(user: @user, provider: @password)

      assert_no_difference "AuthSessionProof.count" do
        Auth::SessionService.append_proof(started.auth_session, @password)
      end
    end

    test "a revoked session stops resolving from its token" do
      started = Auth::SessionService.start(user: @user, provider: @password)

      Auth::SessionService.revoke(started.auth_session)

      assert_nil AuthSession.find_live_by_token(started.token)
    end

    test "revoke_all_for ends every live session a user holds" do
      first = Auth::SessionService.start(user: @user, provider: @password)
      second = Auth::SessionService.start(user: @user, provider: @password)

      Auth::SessionService.revoke_all_for(@user)

      assert_nil AuthSession.find_live_by_token(first.token)
      assert_nil AuthSession.find_live_by_token(second.token)
    end
  end
end
