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

        test "a viewer in the resolved (first) company cannot mutate its assets, even as a writer elsewhere" do
          viewer = create(:user, :viewer, :onboarding_completed, company: @company)
          viewer.company_memberships.find_by!(company: @company).update!(accepted_at: 2.days.ago)
          create(:company_membership, user: viewer, company: create(:company),
                                      role: "employee", accepted_at: 1.day.ago)
          sign_in viewer

          post :create, params: { asset: { name: "doc.md", content_type: "text/markdown" } }
          assert_response :forbidden

          asset = create(:asset, :with_company_scope, scope: @company, created_by: @user)
          delete :destroy, params: { id: asset.id }
          assert_response :forbidden
        end

        test "a user with no active membership gets 404 (no resolvable company)" do
          sign_in create(:user, :onboarding_completed)

          post :create, params: { asset: { name: "doc.md", content_type: "text/markdown" } }
          assert_response :not_found
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
