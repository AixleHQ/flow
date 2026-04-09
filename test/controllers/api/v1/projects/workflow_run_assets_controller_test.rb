# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      class WorkflowRunAssetsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          @workflow = create(:workflow, scope: @company)
          @run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
          @wra = create(:workflow_run_asset, workflow_run: @run)
          sign_in @user
        end

        test "index returns assets json" do
          get :index, params: { project_id: @project.id, workflow_run_id: @run.id }

          assert_response :success
        end

        test "export returns created asset json" do
          exported = create(:asset, :with_project_scope, scope: @project, created_by: @user)
          AssetExportService.any_instance.stubs(:export!).returns({ asset: exported, version: nil })

          post :export, params: { project_id: @project.id, workflow_run_id: @run.id, id: @wra.id }

          assert_response :created
        end

        test "download redirects when file present" do
          WorkflowRunAsset.any_instance.stubs(:file).returns(stub(url: "https://example.com/blob"))

          get :download, params: { project_id: @project.id, workflow_run_id: @run.id, id: @wra.id }

          assert_response :redirect
        end

        test "export_all returns count" do
          out_asset = create(:asset, :with_project_scope, scope: @project, created_by: @user)
          AssetExportService.any_instance.stubs(:export!).returns({ asset: out_asset, version: nil })

          post :export_all, params: { project_id: @project.id, workflow_run_id: @run.id }

          assert_response :created
        end
      end
    end
  end
end
