# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      class AssetsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          sign_in @user
        end

        test "create returns asset json" do
          file_data = document_file_cache_data

          post :create, params: {
            project_id: @project.id,
            asset: {
              name: "proj-doc.md",
              content_type: "text/markdown",
              file: file_data
            }
          }

          assert_response :created
        end

        # Same omission as the company path: the browser sends neither field.
        test "create records file size and content type for a browser-style payload" do
          post :create, params: {
            project_id: @project.id,
            asset: {
              name: "proj-doc.md",
              file: document_file_cache_data
            }
          }

          assert_response :created
          version = response.parsed_body["latestVersion"]
          assert_equal File.size(UploadSupport::DOCUMENT_FILE_PATH), version["fileSize"]
          assert version["contentType"].present?
        end

        # An invalid folder used to reach `save!` unrescued and answer 500, so the client got no
        # way to tell a typo apart from an outage.
        test "create answers 422 and names the offending field for an invalid folder" do
          post :create, params: {
            project_id: @project.id,
            asset: {
              name: "proj-doc.md",
              folder: "docs/sub",
              file: document_file_cache_data
            }
          }

          assert_response :unprocessable_entity
          assert_match(/folder/i, response.parsed_body["error"])
          assert { !@project.assets.exists?(name: "proj-doc.md") }
        end

        test "create trims a padded folder and keeps the spaces inside it" do
          post :create, params: {
            project_id: @project.id,
            asset: { name: "proj-doc.md", folder: "  Q3 reports  ", file: document_file_cache_data }
          }

          assert_response :created
          assert_equal "Q3 reports", response.parsed_body["folder"]
        end

        # The lookup used to key on name alone, so this second upload moved the first asset into
        # the new folder (and appended a version) instead of creating a sibling.
        test "create makes a separate asset when the same filename lands in another folder" do
          post :create, params: {
            project_id: @project.id,
            asset: { name: "readme.md", folder: "docs", file: document_file_cache_data }
          }
          assert_response :created

          assert_difference -> { @project.assets.count }, 1 do
            post :create, params: {
              project_id: @project.id,
              asset: { name: "readme.md", folder: "reports", file: document_file_cache_data }
            }
          end

          assert_response :created
          assert_equal %w[docs reports], @project.assets.where(name: "readme.md").map(&:folder).sort
        end

        test "create appends a version to the existing asset when name and folder both match" do
          post :create, params: {
            project_id: @project.id,
            asset: { name: "readme.md", folder: "docs", file: document_file_cache_data }
          }
          assert_response :created

          assert_no_difference -> { @project.assets.count } do
            post :create, params: {
              project_id: @project.id,
              asset: { name: "readme.md", folder: "docs", file: document_file_cache_data }
            }
          end

          assert_response :created
          assert_equal 2, @project.assets.find_by(name: "readme.md", folder: "docs").versions.count
        end

        test "destroy soft-deletes asset" do
          asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)

          delete :destroy, params: { project_id: @project.id, id: asset.id }

          assert_response :success
        end

        test "download redirects to file url" do
          asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
          create(:asset_version, :with_file, asset: asset, uploaded_by: @user)

          get :download, params: { project_id: @project.id, id: asset.id }

          assert_response :redirect
        end
      end
    end
  end
end
