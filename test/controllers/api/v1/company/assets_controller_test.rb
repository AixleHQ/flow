# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Company
      class AssetsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          sign_in @user
        end

        test "create returns asset json" do
          file_data = document_file_cache_data

          post :create, params: {
            asset: {
              name: "doc.md",
              content_type: "text/markdown",
              file: file_data
            }
          }

          assert_response :created
        end

        test "destroy soft-deletes asset" do
          asset = create(:asset, :with_company_scope, scope: @company, created_by: @user)

          delete :destroy, params: { id: asset.id }

          assert_response :success
        end

        test "download redirects to file url" do
          asset = create(:asset, :with_company_scope, scope: @company, created_by: @user)
          create(:asset_version, :with_file, asset: asset, uploaded_by: @user)

          get :download, params: { id: asset.id }

          assert_response :redirect
        end
      end
    end
  end
end
