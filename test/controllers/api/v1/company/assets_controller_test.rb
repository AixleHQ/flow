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

        test "create answers 422 and names the offending field for an invalid folder" do
          post :create, params: {
            asset: { name: "doc.md", folder: "docs/sub", file: document_file_cache_data }
          }

          assert_response :unprocessable_entity
          assert_match(/folder/i, response.parsed_body["error"])
        end

        # The lookup used to key on name alone, so this second upload moved the first asset into
        # the new folder instead of creating a sibling.
        test "create makes a separate asset when the same filename lands in another folder" do
          post :create, params: {
            asset: { name: "readme.md", folder: "docs", file: document_file_cache_data }
          }
          assert_response :created

          assert_difference -> { @company.assets.count }, 1 do
            post :create, params: {
              asset: { name: "readme.md", folder: "reports", file: document_file_cache_data }
            }
          end

          assert_equal %w[docs reports], @company.assets.where(name: "readme.md").map(&:folder).sort
        end

        # The browser upload path posts only name/folder/file — no size, no type
        # — so the version has to derive both, otherwise the Assets list renders
        # "—" in the Size column for everything uploaded through the UI.
        test "create records file size and content type for a browser-style payload" do
          post :create, params: {
            asset: {
              name: "doc.md",
              file: document_file_cache_data
            }
          }

          assert_response :created
          version = response.parsed_body["latestVersion"]
          assert_equal File.size(UploadSupport::DOCUMENT_FILE_PATH), version["fileSize"]
          assert version["contentType"].present?
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
