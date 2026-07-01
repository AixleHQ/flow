# frozen_string_literal: true

require "test_helper"

class Web::Company::MembersControllerTest < ActionDispatch::IntegrationTest
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

  test "invite as viewer with mismatched email domain succeeds" do
    assert_difference -> { @company.users.where(role: "viewer").count }, 1 do
      post company_members_path, params: {
        user: { email: "client@totally-different-domain.com", name: "External Client", role: "viewer" }
      }
    end
    assert_response :redirect
    invited = @company.users.find_by(email: "client@totally-different-domain.com")
    assert invited.viewer?
  end

  test "update to viewer succeeds" do
    member = create(:user, :employee, company: @company)
    patch company_member_path(member), params: { user: { role: "viewer" } }
    assert_response :redirect
    assert member.reload.viewer?
  end
end
