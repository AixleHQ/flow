# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260927120000_prove_live_sessions_at_cutover")

# The migration exists so that turning this feature on does not send everyone
# who is currently signed in to step-up. What it must not do is manufacture a
# proof it cannot derive.
#
# Setting a password creates its identity (User#link_password_identity), so a
# plain factory user already holds exactly one provider — the same shape as a
# password user on a deployment the backfill has just run against.
class ProveLiveSessionsAtCutoverTest < ActiveSupport::TestCase
  setup do
    @migration = ProveLiveSessionsAtCutover.new
    @password = IdentityProvider.deployment!("password")
    @google = IdentityProvider.deployment!("google")
  end

  def migrate
    @migration.suppress_messages { @migration.up }
  end

  def proofs_for(user_session)
    UserSessionProof.where(user_session: user_session)
  end

  # The 73 Google users on a deployment like ours: no password, one identity.
  def google_only_user
    user = create(:user)
    user.user_identities.destroy_all
    user.update_column(:password_digest, nil)
    create(:user_identity, user: user, identity_provider: @google)
    user
  end

  test "a live session is proved by the one provider its user could have used" do
    user = create(:user)
    user_session = create(:user_session, user: user, created_at: 3.days.ago)

    migrate

    proof = proofs_for(user_session).sole
    assert_equal @password, proof.identity_provider
    # The proof dates from the sign-in, not from the deploy: that is when the
    # person actually authenticated.
    assert_in_delta user_session.created_at.to_f, proof.proved_at.to_f, 1
  end

  test "a user who only ever had Google is proved by Google" do
    user_session = create(:user_session, user: google_only_user)

    migrate

    assert_equal @google, proofs_for(user_session).sole.identity_provider
  end

  test "a revoked session is left alone" do
    user_session = create(:user_session, user: create(:user), revoked_at: 1.hour.ago)

    migrate

    assert_empty proofs_for(user_session)
  end

  test "a user holding two providers is sent to step-up instead of guessed at" do
    user = create(:user)
    create(:user_identity, user: user, identity_provider: @google)
    user_session = create(:user_session, user: user)

    migrate

    assert_empty proofs_for(user_session),
      "picking one of two providers would be inventing the proof"
  end

  test "a user holding no identity is left unproved" do
    user = create(:user)
    user.user_identities.destroy_all
    user_session = create(:user_session, user: user)

    migrate

    assert_empty proofs_for(user_session)
  end

  test "running it again neither duplicates nor raises" do
    user_session = create(:user_session, user: create(:user))

    migrate
    migrate

    assert_equal 1, proofs_for(user_session).count
  end

  test "a proved session satisfies a company that accepts that provider" do
    company = create(:company)
    user = create(:user, company: company)
    user_session = create(:user_session, user: user)

    migrate

    assert Auth::PolicyResolver.satisfied?(company: company, user_session: user_session, user: user)
  end
end
