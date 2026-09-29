# frozen_string_literal: true

require "test_helper"

# AD-6: a session records HOW it was authenticated, and those records append.
class Auth::SessionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, company: create(:company))
    @session = create(:user_session, user: @user)
    @password = IdentityProvider.password
    @google = IdentityProvider.deployment!("google")
  end

  test "records a proof for the method used" do
    assert_difference "UserSessionProof.count", 1 do
      Auth::SessionService.record_proof(@session, @password)
    end

    assert_equal [ @password.id ], @session.reload.proved_provider_ids
  end

  test "a second method appends rather than replacing the first" do
    Auth::SessionService.record_proof(@session, @password)
    Auth::SessionService.record_proof(@session, @google)

    assert_equal [ @password.id, @google.id ].sort, @session.reload.proved_provider_ids.sort
  end

  test "proving the same method twice refreshes the one row" do
    first = Auth::SessionService.record_proof(@session, @password)
    travel 1.minute

    assert_no_difference "UserSessionProof.count" do
      Auth::SessionService.record_proof(@session, @password)
    end

    assert_operator first.reload.proved_at, :>, 30.seconds.ago
  end

  test "records nothing without a session or a provider" do
    assert_no_difference "UserSessionProof.count" do
      assert_nil Auth::SessionService.record_proof(nil, @password)
      assert_nil Auth::SessionService.record_proof(@session, nil)
    end
  end

  test "ending a session takes its proofs with it" do
    Auth::SessionService.record_proof(@session, @password)

    assert_difference "UserSessionProof.count", -1 do
      @session.destroy!
    end
  end
end
