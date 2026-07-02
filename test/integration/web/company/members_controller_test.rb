# frozen_string_literal: true

require "test_helper"

class Web::Company::MembersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders members page" do
    get company_members_path
    assert_inertia_page "Company/Members/Index"
  end

  test "create redirects on success" do
    post company_members_path, params: {
      user: { email: "newmember@example.com", name: "New Member", role: "employee" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    member = create(:user, company: @company)

    patch company_member_path(member), params: {
      user: { role: "admin" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    member = create(:user, company: @company)

    delete company_member_path(member)
    assert_response :redirect
  end

  # Regression (originally #379): removing a member who owns projects used to
  # raise a 500, because projects.owner_id is NOT NULL and the destroy nullified
  # it. Removal no longer touches the User row at all — it revokes the
  # MEMBERSHIP — so the owner FK can never be violated and the guard that used
  # to block this is unnecessary. What must still hold: no crash, the user row
  # survives, and the project keeps its owner.
  #
  # NOTE: this deliberately leaves a project owned by a non-member. Reassigning
  # or blocking that is a product decision, tracked separately.
  test "destroy revokes the membership without touching a project-owning member" do
    member = create(:user, company: @company)
    project = create(:project, company: @company, owner: member)

    assert_difference -> { @company.users.count }, -1 do
      delete company_member_path(member)
    end

    assert_response :redirect
    assert User.exists?(member.id)
    assert_equal member.id, project.reload.owner_id
    assert_equal "revoked", @company.company_memberships.find_by(user_id: member.id).state
  end

  test "invite as viewer with mismatched email domain succeeds" do
    assert_difference -> { @company.company_memberships.with_role(:viewer).count }, 1 do
      post company_members_path, params: {
        user: { email: "client@totally-different-domain.com", name: "External Client", role: "viewer" }
      }
    end
    assert_response :redirect
    # company.users is scoped to ACTIVE memberships — look the invitee up globally.
    invited = User.find_by!(email: "client@totally-different-domain.com")
    assert @company.company_memberships.find_by(user: invited).viewer?
  end

  test "update to viewer succeeds" do
    member = create(:user, :employee, company: @company)
    patch company_member_path(member), params: { user: { role: "viewer" } }
    assert_response :redirect
    assert @company.company_memberships.find_by(user: member).viewer?
  end

  test "index supports searching members by name/email (ransack over memberships)" do
    create(:user, :employee, company: @company, name: "Findable Fred")
    create(:user, :employee, company: @company, name: "Other Olga")

    get company_members_path, params: { q: { user_name_or_user_email_cont: "Findable" } }
    names = inertia.props[:users].map { |u| u[:name] }
    assert_includes names, "Findable Fred"
    assert_not_includes names, "Other Olga"
  end

  # === graceful state handling (no 500s) ===

  test "update with a state event invalid for the current state reports an error instead of raising" do
    member = create(:user, :employee, company: @company, membership_state: "invited")

    patch company_member_path(member), params: { user: { state_event: "suspend" } }

    assert_redirected_to company_members_path
    assert @company.company_memberships.find_by(user: member).invited?
  end

  test "update and destroy 404 on a revoked membership" do
    member = create(:user, :employee, company: @company)
    @company.company_memberships.find_by!(user: member).revoke!

    patch company_member_path(member), params: { user: { role: "admin" } }
    assert_response :not_found

    delete company_member_path(member)
    assert_response :not_found
  end

  test "concurrent invite of the same new email reports 'already invited' instead of 500" do
    # The race the DB unique index catches: no row exists at find time, but the
    # INSERT loses. Single-threaded, the only way to reach the controller's
    # RecordNotUnique rescue is to make the collaborator's save raise — stubbed
    # on one real instance, not any_instance (testing doctrine R6).
    racing_user = User.new(email: "race@example.com", name: "Race")
    racing_user.stubs(:save).raises(ActiveRecord::RecordNotUnique.new("duplicate key"))
    User.stubs(:find_or_initialize_by).returns(racing_user)

    post company_members_path, params: {
      user: { email: "race@example.com", name: "Race", role: "employee" }
    }

    assert_redirected_to company_members_path
  end

  test "inviting a super admin's email is rejected with a form error" do
    super_admin = create(:user, :super_admin)

    assert_no_difference -> { CompanyMembership.count } do
      post company_members_path, params: { user: { email: super_admin.email, name: "SA" } }
    end
    assert_redirected_to company_members_path
  end

  # === invite edge branches + email enqueueing ===

  test "inviting an existing user from another company creates an invited membership and enqueues the email" do
    other_company = create(:company)
    existing = create(:user, :employee, :onboarding_completed, company: other_company)

    assert_difference -> { @company.company_memberships.count }, 1 do
      assert_enqueued_emails 1 do
        post company_members_path, params: { user: { email: existing.email, role: "employee" } }
      end
    end

    assert_redirected_to company_members_path
    membership = @company.company_memberships.find_by!(user: existing)
    assert membership.invited?
    assert_equal @user, membership.invited_by
    # The other company's membership is untouched — the user now has two.
    assert_equal 2, existing.company_memberships.count
  end

  test "inviting an already-invited member takes the resend path: fresh email, invited_at touched, no new row" do
    member = create(:user, company: @company, membership_state: "invited")
    membership = @company.company_memberships.find_by!(user: member)
    membership.update!(invited_at: 2.days.ago)

    assert_no_difference -> { CompanyMembership.count } do
      assert_enqueued_email_with MembershipMailer, :invitation, args: [ membership ] do
        post company_members_path, params: { user: { email: member.email } }
      end
    end

    assert_redirected_to company_members_path
    assert_operator membership.reload.invited_at, :>, 1.minute.ago
  end

  test "resend on an ACTIVE membership is rejected and sends nothing" do
    member = create(:user, :employee, company: @company)

    assert_no_enqueued_emails do
      post resend_company_member_path(member)
    end

    assert_redirected_to company_members_path
    assert_equal "Only pending invitations can be re-sent", flash[:alert]
  end

  test "re-inviting a revoked member fires the reinvite event and enqueues a fresh invitation email" do
    member = create(:user, :employee, company: @company)
    membership = @company.company_memberships.find_by!(user: member)
    membership.revoke!

    assert_no_difference -> { CompanyMembership.count } do
      assert_enqueued_email_with MembershipMailer, :invitation, args: [ membership ] do
        post company_members_path, params: { user: { email: member.email, role: "viewer" } }
      end
    end

    assert membership.reload.invited?
    assert_equal @user, membership.invited_by
  end

  test "inviting an existing ACTIVE member reports a form error and sends nothing" do
    member = create(:user, :employee, company: @company)

    assert_no_difference -> { CompanyMembership.count } do
      assert_no_enqueued_emails do
        post company_members_path, params: { user: { email: member.email } }
      end
    end

    assert_redirected_to company_members_path
  end

  # === re-invite / resend token semantics ===

  test "re-inviting a revoked member goes through the reinvite event and kills old links" do
    member = create(:user, :employee, company: @company)
    membership = @company.company_memberships.find_by!(user: member)
    membership.update!(invited_at: 2.days.ago)
    old_token = membership.generate_token_for(:invitation)
    membership.revoke!

    post company_members_path, params: { user: { email: member.email, role: "viewer" } }

    assert_redirected_to company_members_path
    membership.reload
    assert membership.invited?
    assert membership.viewer?
    assert_nil membership.accepted_at
    assert_nil CompanyMembership.find_by_token_for(:invitation, old_token)
  end

  test "resend rotates invited_at so the previously mailed link stops working" do
    member = create(:user, company: @company, membership_state: "invited")
    membership = @company.company_memberships.find_by!(user: member)
    membership.update!(invited_at: 2.days.ago)
    old_token = membership.generate_token_for(:invitation)

    post resend_company_member_path(member)

    assert_redirected_to company_members_path
    assert_operator membership.reload.invited_at, :>, 1.minute.ago
    assert_nil CompanyMembership.find_by_token_for(:invitation, old_token)
  end
end
