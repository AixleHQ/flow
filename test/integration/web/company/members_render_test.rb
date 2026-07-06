# frozen_string_literal: true

require "test_helper"

# Render-smoke request test for Web::Company::MembersController (docs/testing.md §2):
# GET each page the controller renders as an authorized admin and assert the Inertia
# component + status. Companion to members_authorization_test.rb (permit/forbid matrix).
#
# Pages covered:
#   - Company/Members/Index  (index)
class Web::Company::MembersRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    Bullet.enable = false # index eager-loads :invited_by; the unused-eager-loading gate would trip
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the members page with the company's users" do
    member = create(:user, :employee, company: @company)

    get company_members_path
    assert_response :success
    assert_inertia_page "Company/Members/Index"
    assert_inertia_props do |props|
      emails = props[:users].map { |u| u[:email] }
      props[:users].length == 2 && emails.include?(@user.email) && emails.include?(member.email)
    end
  end
end
