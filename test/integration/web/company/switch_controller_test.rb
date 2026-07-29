# frozen_string_literal: true

require "test_helper"

class Web::Company::SwitchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company_a = create(:company, name: "Alpha")
    @company_b = create(:company, name: "Beta")
    @user = create(:user, :admin, :onboarding_completed, company: @company_a, password: AuthHelper::TEST_PASSWORD)
    # Deterministic default: A is the oldest accepted membership.
    @membership_a = @user.company_memberships.find_by!(company: @company_a).tap { |m| m.update!(accepted_at: 2.days.ago) }
    # Per-company onboarding: B needs its own completed onboarding, or every
    # B-scoped page redirects to /onboarding instead of rendering.
    @membership_b = create(:company_membership, :viewer, user: @user, company: @company_b,
                                                accepted_at: 1.day.ago,
                                                onboarding_state: "completed",
                                                onboarding_completed_at: Time.current,
                                                position: "dev", preferred_agent_language: "en")
    sign_in_as(@user)
  end

  def current_company_id
    get company_projects_path
    return nil unless response.status == 200

    inertia.props[:currentUser][:currentCompany][:id]
  end

  test "switch to a member company updates the session and re-scopes subsequent pages" do
    assert_equal @company_a.id, current_company_id

    post company_switch_path, params: { company_id: @company_b.id }
    assert_redirected_to company_projects_path

    assert_equal @company_b.id, current_company_id
  end

  test "switch to a non-member company_id is rejected and leaves the session unchanged" do
    stranger_company = create(:company)

    post company_switch_path, params: { company_id: stranger_company.id }
    assert_response :not_found

    assert_equal @company_a.id, current_company_id
  end

  test "switch to a company where the membership is not active is rejected" do
    @membership_b.revoke!

    post company_switch_path, params: { company_id: @company_b.id }
    assert_response :not_found

    assert_equal @company_a.id, current_company_id
  end

  test "revoking the current membership falls back to the remaining one on the next request" do
    post company_switch_path, params: { company_id: @company_b.id }
    assert_equal @company_b.id, current_company_id

    @membership_b.revoke!

    assert_equal @company_a.id, current_company_id
  end

  test "revoking the last membership signs the user out on the next request" do
    # A second admin so the last-admin guard allows revoking @membership_a.
    create(:company_membership, :admin, user: create(:user), company: @company_a)
    @membership_b.revoke!
    @membership_a.revoke!

    get company_projects_path
    assert_redirected_to login_path(error: "no_active_membership")

    # Session is gone: the next request is treated as unauthenticated.
    get company_projects_path
    assert_redirected_to login_path
  end
  # === stickiness across sessions (users.last_company_id) ===
  # session[:current_company_id] dies with the cookie. Without a persisted hint
  # the user silently snaps back to their OLDEST company on the next login,
  # which for a consultant whose home company is the newest one is wrong every
  # single time.

  test "the switched-to company is still current after signing out and back in" do
    post company_switch_path, params: { company_id: @company_b.id }
    assert_equal @company_b.id, current_company_id
    assert_equal @company_b.id, @user.reload.last_company_id

    # A fresh session: the switcher choice lives only in the cookie, so without
    # the persisted hint this would resolve back to A (oldest accepted).
    delete logout_path
    sign_in_as(@user)

    assert_equal @company_b.id, current_company_id
  end

  test "a remembered company that is no longer active falls back instead of resolving" do
    delete logout_path
    @user.update_column(:last_company_id, @company_b.id)
    @membership_b.update!(state: "revoked")
    sign_in_as(@user)

    # Falls back to the remaining active membership, and re-points the hint.
    assert_equal @company_a.id, current_company_id
    assert_equal @company_a.id, @user.reload.last_company_id
  end
end
