# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API workflow-run-assets endpoints,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::WorkflowRunAssetsPolicy
#          < Web::Company::Projects::WorkflowRunAssetsPolicy
#          < Web::Company::ApplicationPolicy):
#   reads  (index, download)     => project_accessible?
#   writes (export, export_all)  => project_writable?
#     (project_writable? == project_accessible? && !current_user.read_only?)
#
# current_project is resolved via Project.for_user(current_user).find(:project_id),
# so an inaccessible project (stranger / foreign admin) raises RecordNotFound (404)
# in the authorization before_action, before the policy runs.
#
# `download` is a read, but once authorized it redirects (302) to the Shrine file
# URL rather than rendering 200 -- so the fixture asset carries a stored file and
# the read matrix asserts :redirect. `export` / `export_all` run AssetExportService
# for real (a local service -- no Temporal/vendor calls, nothing stubbed) and render
# 201, which asserts as :success; export_params is a permit (no require), so the
# allowed writes need no body.
class Api::V1::Projects::WorkflowRunAssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas

    @workflow = create(:workflow, scope: @company)
    @run = create(:workflow_run, workflow: @workflow, project: @project, user: @owner)
    @wra = create(:workflow_run_asset, workflow_run: @run)
    @wra.file = WorkflowRunAssetUploader.upload(StringIO.new("workflow run asset content"), :store)
    @wra.save!
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) do
      get api_v1_project_workflow_run_workflow_run_assets_path(@project, @run)
    end
  end

  # download is a project read whose allowed outcome is a 302 redirect to the file
  # URL (the fixture asset has a stored file), so it uses the read expectations with
  # a :redirect allowed status. The read-only viewer is a collaborator, so the read
  # is permitted for it too.
  test "download is a project read (allowed roles redirect to the file URL)" do
    assert_role_matrix(
      { owner: :allowed_read, admin: :allowed_read, collaborator: :allowed_read,
        viewer: :allowed_read, stranger: :not_found, foreign_admin: :not_found },
      transport: :api, allowed_status: :redirect
    ) do
      get download_api_v1_project_workflow_run_workflow_run_asset_path(@project, @run, @wra)
    end
  end

  test "export is a project write" do
    assert_project_write(transport: :api) do
      post export_api_v1_project_workflow_run_workflow_run_asset_path(@project, @run, @wra), as: :json
    end
  end

  test "export_all is a project write" do
    assert_project_write(transport: :api) do
      post export_all_api_v1_project_workflow_run_workflow_run_assets_path(@project, @run), as: :json
    end
  end
end
