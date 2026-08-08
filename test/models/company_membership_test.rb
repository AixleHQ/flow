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

  # === configured_agents ordering ===

  # The run/session forms preselect configured_agents.first when the member has
  # no default credential, so an unordered scope made the choice a coin flip.
  test "configured_agents lists this company's credentials newest first" do
    membership = create(:company_membership, user: @user, company: @company)
    travel_to 2.days.ago do
      create(:agent_credential, user: @user, company: @company, agent_type: "cursor_cli")
    end
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    assert_equal %w[claude_code cursor_cli], membership.configured_agents
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

  # === owned-project transfer on revocation ===
  # Project#owner_belongs_to_company requires an ACTIVE membership, so a revoked
  # owner leaves the project failing validation on any later save. Revocation
  # therefore either moves ownership or refuses.

  test "revoking an owner transfers their projects to the company's oldest active admin" do
    owner = create(:user, :employee, company: @company)
    newer_admin = create(:user, :admin, company: @company)
    newer_admin.company_memberships.sole.update!(accepted_at: 1.hour.ago)
    oldest_admin = create(:user, :admin, company: @company)
    oldest_admin.company_memberships.sole.update!(accepted_at: 3.days.ago)
    project = create(:project, company: @company, owner: owner)

    membership = owner.company_memberships.sole
    membership.aasm(:state).fire(:revoke)
    assert membership.save, membership.errors.full_messages.to_sentence

    assert_equal oldest_admin.id, project.reload.owner_id
    assert project.valid?
  end

  test "revoking an owner is refused when the company has no other active admin" do
    owner = create(:user, :employee, company: @company)
    create(:user, :employee, company: @company)
    project = create(:project, company: @company, owner: owner)

    membership = owner.company_memberships.sole
    membership.aasm(:state).fire(:revoke)

    assert_not membership.save
    assert_includes membership.errors[:base].to_sentence, "no other admin"
    assert_equal owner.id, project.reload.owner_id
    assert membership.reload.active?
  end

  test "revoking a member who owns nothing needs no heir" do
    member = create(:user, :employee, company: @company)

    membership = member.company_memberships.sole
    membership.aasm(:state).fire(:revoke)

    assert membership.save, membership.errors.full_messages.to_sentence
    assert membership.reload.revoked?
  end

  test "projects in OTHER companies are left alone when a membership is revoked" do
    other_company = create(:company)
    owner = create(:user, :employee, company: @company)
    create(:company_membership, user: owner, company: other_company)
    create(:user, :admin, company: @company)
    elsewhere = create(:project, company: other_company, owner: owner)

    membership = owner.company_memberships.find_by!(company: @company)
    membership.aasm(:state).fire(:revoke)
    assert membership.save, membership.errors.full_messages.to_sentence

    assert_equal owner.id, elsewhere.reload.owner_id
  end
end
