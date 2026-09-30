# frozen_string_literal: true

require "test_helper"

# The company sign-in policy holds on the JSON API as it does on web pages: a
# session that has not proved a method the project's company accepts is sent to
# that company's step-up, whichever company the browser is on.
class Api::V1::CompanyAuthPolicyTest < ActionDispatch::IntegrationTest
  setup do
    @open_company = create(:company)
    @sso_company = create(:company)
    @user = create(:user, :onboarding_completed, company: @open_company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    create(:company_membership, user: @user, company: @sso_company, state: "active",
                                accepted_at: Time.current, onboarding_state: "completed",
                                onboarding_completed_at: Time.current)

    @sso = create(:identity_provider, company: @sso_company, kind: "oidc", name: "SSO Co")
    CompanyAuthPolicy.where(company: @sso_company).update_all(enabled: false)
    create(:company_auth_policy, company: @sso_company, identity_provider: @sso, enabled: true)

    @open_project = create(:project, company: @open_company, owner: @user)
    create(:board, project: @open_project)
    @sso_project = create(:project, company: @sso_company, owner: @user)
    create(:board, project: @sso_project)

    sign_in_as(@user)
  end

  def board_tasks(project)
    get "/api/v1/projects/#{project.id}/tasks", headers: { "ACCEPT" => "application/json" }
  end

  test "a password-only session is sent to the SSO company's step-up" do
    board_tasks(@sso_project)

    assert_response :forbidden
    assert_equal "step_up_required", response.parsed_body["error"]
    assert_equal step_up_path(company_id: @sso_company.id), response.parsed_body["stepUpUrl"]
  end

  test "the step-up it points to asks for the SSO company's method" do
    board_tasks(@sso_project)

    get response.parsed_body["stepUpUrl"], headers: { "X-Inertia" => "true" }

    assert_response :success
    assert_inertia_props { |props| assert_equal [ "oidc" ], props[:methods].map { |m| m[:kind] } }
  end

  test "a proof of the SSO company's method lets the request through" do
    Auth::SessionService.record_proof(UserSession.live.find_by!(user: @user), @sso)

    board_tasks(@sso_project)

    assert_response :success
  end

  test "a company on the default policy is unaffected" do
    board_tasks(@open_project)

    assert_response :success
  end
end
