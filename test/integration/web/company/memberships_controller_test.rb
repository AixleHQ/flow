# frozen_string_literal: true

require "test_helper"

class Web::Company::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company_a = create(:company, name: "Alpha")
    @company_b = create(:company, name: "Beta")
    @user = create(:user, :employee, :onboarding_completed, company: @company_a, password: AuthHelper::TEST_PASSWORD)
    @membership_a = @user.company_memberships.find_by!(company: @company_a).tap { |m| m.update!(accepted_at: 2.days.ago) }
    @membership_b = create(:company_membership, :viewer, user: @user, company: @company_b, accepted_at: 1.day.ago)
    sign_in_as(@user)
  end

  def current_company_id
    get company_projects_path
    inertia.props[:currentUser][:currentCompany][:id]
  end

  test "leaving a non-current membership revokes it and keeps the current company" do
    delete company_membership_path(@membership_b)

    assert_redirected_to profile_path
    assert @membership_b.reload.revoked?
    assert_equal @company_a.id, current_company_id
  end

  test "leaving the current membership falls back to the remaining one" do
    assert_equal @company_a.id, current_company_id

    delete company_membership_path(@membership_a)

    assert_redirected_to profile_path
    assert @membership_a.reload.revoked?
    assert_equal @company_b.id, current_company_id
  end

  test "the sole admin cannot leave: blocked with a flash alert" do
    admin = create(:user, :admin, :onboarding_completed, company: @company_a, password: AuthHelper::TEST_PASSWORD)
    admin_membership = admin.company_memberships.find_by!(company: @company_a)

    delete logout_path
    sign_in_as(admin)
    delete company_membership_path(admin_membership)

    assert_redirected_to profile_path
    assert_match(/last admin/i, flash[:alert])
    assert admin_membership.reload.active?
  end

  test "leaving the last membership signs the user out" do
    @membership_b.revoke!

    delete company_membership_path(@membership_a)

    assert_redirected_to login_path
    assert @membership_a.reload.revoked?

    get company_projects_path
    assert_redirected_to login_path
  end

  test "a suspended member can still leave the company" do
    @membership_b.suspend!

    delete company_membership_path(@membership_b)

    assert_redirected_to profile_path
    assert @membership_b.reload.revoked?
  end

  test "a signed-in user whose memberships were all revoked is signed out with a distinct error" do
    @membership_a.revoke!
    @membership_b.revoke!

    get company_projects_path

    assert_redirected_to login_path(error: "no_active_membership")
  end

  test "cannot leave with someone else's membership id" do
    other = create(:user, :employee, company: @company_a)
    other_membership = other.company_memberships.find_by!(company: @company_a)

    delete company_membership_path(other_membership)

    # Pundit denial follows the app-wide convention: redirect, never touch the record.
    assert_response :redirect
    assert other_membership.reload.active?
  end
end
