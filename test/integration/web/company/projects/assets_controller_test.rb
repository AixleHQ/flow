# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders assets page" do
    create_list(:asset, 2, :with_project_scope, scope: @project, created_by: @user)

    get company_project_assets_path(@project)
    assert_inertia_page "Projects/Assets/AssetsPage"
  end
end
