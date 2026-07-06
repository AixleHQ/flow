# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AssetsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the assets page with the accessible assets" do
    create_list(:asset, 2, :with_project_scope, scope: @project, created_by: @user)

    get company_project_assets_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Assets/AssetsPage"
    assert_inertia_props do |props|
      props[:assets].size == 2
    end
  end

  test "index includes asset versions when history_asset_id is given" do
    asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
    create(:asset_version, asset: asset, uploaded_by: @user, version: 1)

    get company_project_assets_path(@project, history_asset_id: asset.id)

    assert_response :success
    assert_inertia_page "Projects/Assets/AssetsPage"
    assert_inertia_props do |props|
      props[:assetVersions].size == 1
    end
  end
end
