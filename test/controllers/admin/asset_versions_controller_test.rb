# frozen_string_literal: true

require "test_helper"

module Admin
  class AssetVersionsControllerTest < Admin::ActionControllerTestCase
    setup do
      @company = create(:company)
      @user = create(:user, :with_company, company: @company)
      @asset = create(:asset, :with_company_scope, scope: @company, created_by: @user)
      @version = create(:asset_version, asset: @asset, uploaded_by: @user)
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should show asset_version" do
      get :show, params: { id: @version.id }
      assert_response :success
    end
  end
end
