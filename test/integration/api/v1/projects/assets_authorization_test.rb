# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API project-assets endpoints, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::AssetsPolicy < Web::Company::Projects::AssetsPolicy):
#   read  (download)         => project_accessible?
#   writes (create/destroy)  => project_writable?  (accessible && !read_only?)
# Inaccessible project (stranger / foreign admin) => 404: current_project is
# resolved via Project.for_user(current_user).find(:project_id), which raises
# RecordNotFound before the policy runs. The viewer is a collaborator (so may
# read) but is read_only?, so writes are denied (403 — project_writable? is
# false).
#
# `download` (once authorized) redirects to the Shrine file URL, so an allowed
# download asserts :redirect (302), not :success — hence the escape hatch with
# allowed_status: :redirect. A project has no auto-created asset, so a scoped
# asset + a stored file version are built here.
class Api::V1::Projects::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @asset = create(:asset, :with_project_scope, scope: @project, created_by: @owner)
    create(:asset_version, :with_file, asset: @asset, uploaded_by: @owner)
  end

  teardown { teardown_authz }

  # download is a project read, but the action redirects to the file URL, so
  # allowed roles get a 302 (not a 2xx) — allowed_status: :redirect captures that.
  test "download is a project read (allowed roles redirect to the file URL)" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :not_found, foreign_admin: :not_found },
      transport: :api, allowed_status: :redirect
    ) { get download_api_v1_project_asset_path(@project, @asset) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_assets_path(@project),
           params: { asset: { name: "authz-asset.md", content_type: "text/markdown", file: document_file_cache_data } },
           as: :json
    end
  end

  # destroy soft-deletes, so build a throwaway asset per role iteration to keep
  # @asset intact for the allowed roles that follow.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_asset_path(@project, create(:asset, :with_project_scope, scope: @project, created_by: @owner))
    end
  end
end
