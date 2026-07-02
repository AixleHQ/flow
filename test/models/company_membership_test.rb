# frozen_string_literal: true

require "test_helper"

class CompanyMembershipTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user)
  end

  # === state machine ===

  test "starts invited and accept! moves to active setting accepted_at" do
    membership = create(:company_membership, :invited, user: @user, company: @company)
    assert membership.invited?
    assert_nil membership.accepted_at

    assert membership.accept!
    assert membership.reload.active?
    assert membership.accepted_at.present?
  end

  test "revoke! works from invited, active and suspended" do
    %i[invited suspended].each do |state|
      membership = create(:company_membership, state, user: create(:user), company: @company)
      assert membership.revoke!
      assert membership.reload.revoked?
    end

    active = create(:company_membership, user: create(:user), company: @company)
    assert active.revoke!
    assert active.reload.revoked?
  end

  test "suspend and reactivate cycle" do
    membership = create(:company_membership, user: @user, company: @company)
    assert membership.suspend!
    assert membership.suspended?
    assert membership.reactivate!
    assert membership.active?
  end

  test "accept is not allowed from active" do
    membership = create(:company_membership, user: @user, company: @company)
    assert_not membership.may_accept?
  end

  # === role predicates ===

  test "role predicates" do
    assert create(:company_membership, user: @user, company: @company).employee?
    assert create(:company_membership, :admin, user: create(:user), company: @company).admin?
    assert create(:company_membership, :viewer, user: create(:user), company: @company).viewer?
  end

  # === uniqueness ===

  test "user can have only one membership per company" do
    create(:company_membership, user: @user, company: @company)
    dup = build(:company_membership, user: @user, company: @company)
    assert_not dup.valid?
    assert dup.errors[:user_id].present?

    other_company = create(:company)
    assert build(:company_membership, user: @user, company: other_company).valid?
  end

  # === last-admin guard ===

  test "demoting the sole active admin is invalid" do
    admin = create(:company_membership, :admin, user: @user, company: @company)
    admin.role = "employee"
    assert_not admin.valid?
    assert_includes admin.errors[:base].to_sentence, "last admin"
  end

  # The controllers never use the bang transitions (aasm 6 raises
  # RecordInvalid from those); they fire the event and then `save`, so the
  # last-admin guard surfaces as a validation error. Assert that same path.
  test "revoking the sole active admin is blocked" do
    admin = create(:company_membership, :admin, user: @user, company: @company)

    admin.aasm(:state).fire(:revoke)
    assert_not admin.save
    assert_includes admin.errors[:base].to_sentence, "last admin"
    assert admin.reload.active?
  end

  test "suspending the sole active admin is blocked" do
    admin = create(:company_membership, :admin, user: @user, company: @company)

    admin.aasm(:state).fire(:suspend)
    assert_not admin.save
    assert_includes admin.errors[:base].to_sentence, "last admin"
    assert admin.reload.active?
  end

  test "demote is valid once a second active admin exists" do
    admin = create(:company_membership, :admin, user: @user, company: @company)
    create(:company_membership, :admin, user: create(:user), company: @company)

    admin.role = "employee"
    assert admin.valid?
    assert admin.save
  end

  test "an invited admin does not count as an active admin" do
    admin = create(:company_membership, :admin, user: @user, company: @company)
    create(:company_membership, :admin, :invited, user: create(:user), company: @company)

    admin.role = "employee"
    assert_not admin.valid?
  end

  test "reinvite moves revoked back to invited" do
    membership = create(:company_membership, :revoked, user: @user, company: @company)

    assert membership.may_reinvite?
    assert membership.reinvite!
    assert membership.reload.invited?
  end

  test "reinvite is not allowed from active" do
    membership = create(:company_membership, user: @user, company: @company)
    assert_not membership.may_reinvite?
  end

  # === default_order (fallback company resolution) ===

  test "default_order sorts NULL accepted_at first, then oldest accepted, id as tiebreak" do
    newest = create(:company_membership, user: @user, company: create(:company), accepted_at: 1.day.ago)
    oldest = create(:company_membership, user: @user, company: create(:company), accepted_at: 3.days.ago)
    legacy = create(:company_membership, user: @user, company: create(:company), accepted_at: nil)

    assert_equal [ legacy, oldest, newest ], @user.company_memberships.default_order.to_a
  end

  # === cable disconnect on revoke ===

  test "revoking a membership disconnects the user's cable connections" do
    membership = create(:company_membership, user: @user, company: @company)

    remote = mock("remote_connections")
    remote.expects(:where).with(current_user: @user).returns(stub(disconnect: true))
    ActionCable.server.stubs(:remote_connections).returns(remote)

    assert membership.revoke!
  end

  # === invitation token ===

  test "invitation token roundtrip" do
    membership = create(:company_membership, :invited, user: @user, company: @company)
    token = membership.generate_token_for(:invitation)

    assert_equal membership, CompanyMembership.find_by_token_for(:invitation, token)
  end

  test "invitation token is invalidated by a state change" do
    membership = create(:company_membership, :invited, user: @user, company: @company)
    token = membership.generate_token_for(:invitation)

    membership.accept!
    assert_nil CompanyMembership.find_by_token_for(:invitation, token)
  end

  test "a revoked-then-reinvited membership does not revalidate the old link" do
    membership = create(:company_membership, :invited, user: @user, company: @company, invited_at: 2.days.ago)
    old_token = membership.generate_token_for(:invitation)

    membership.revoke!
    membership.assign_attributes(invited_at: Time.current)
    membership.aasm(:state).fire(:reinvite)
    membership.save!

    assert_nil CompanyMembership.find_by_token_for(:invitation, old_token)
    assert_equal membership, CompanyMembership.find_by_token_for(:invitation, membership.generate_token_for(:invitation))
  end

  test "touching invited_at (re-send) invalidates the previously issued token" do
    membership = create(:company_membership, :invited, user: @user, company: @company, invited_at: 2.days.ago)
    old_token = membership.generate_token_for(:invitation)

    membership.update!(invited_at: Time.current)

    assert_nil CompanyMembership.find_by_token_for(:invitation, old_token)
  end

  test "invitation token expires after 7 days" do
    membership = create(:company_membership, :invited, user: @user, company: @company)
    token = membership.generate_token_for(:invitation)

    travel 8.days do
      assert_nil CompanyMembership.find_by_token_for(:invitation, token)
    end
  end
end
