# frozen_string_literal: true

require "test_helper"

class Admin::SessionAdmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
    @owner = create(:user, company: @company)
  end

  test "the page reports what the environment currently resolves to" do
    with_scope_defaults(project: 3)

    get admin_session_admission_path

    assert_response :success
    assert_match(/3 each/, response.body)
    assert_match(/queue per user, 2 at a time/, response.body)
  end
end
