# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      class WorkflowsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          @workflow = create(:workflow, scope: @project)
          sign_in @user
        end

        test "show returns workflow json" do
          get :show, params: { project_id: @project.id, id: @workflow.id }

          assert_response :success
        end

        test "update returns workflow json" do
          patch :update, params: {
            project_id: @project.id,
            id: @workflow.id,
            workflow: { name: "Project WF renamed" }
          }

          assert_response :success
        end

        test "update persists inherit_all_project_resources into config" do
          patch :update, params: {
            project_id: @project.id,
            id: @workflow.id,
            workflow: { config: { inheritAllProjectResources: true } }
          }, as: :json

          assert_response :success
          @workflow.reload
          assert_equal true, @workflow.config["inherit_all_project_resources"]
        end

        test "update can disable inherit_all_project_resources" do
          @workflow.update!(config: { "inherit_all_project_resources" => true })

          patch :update, params: {
            project_id: @project.id,
            id: @workflow.id,
            workflow: { config: { inheritAllProjectResources: false } }
          }, as: :json

          assert_response :success
          @workflow.reload
          assert_equal false, @workflow.config["inherit_all_project_resources"]
        end

        test "update persists multiple config keys together" do
          patch :update, params: {
            project_id: @project.id,
            id: @workflow.id,
            workflow: { config: { inheritAllProjectResources: true, base_tool_ids: [ 1, 2 ] } }
          }, as: :json

          assert_response :success
          @workflow.reload
          assert_equal [ 1, 2 ], @workflow.config["base_tool_ids"]
          assert_equal true, @workflow.config["inherit_all_project_resources"]
        end

        test "update preserves pre-existing config keys when only one config key is updated" do
          @workflow.update!(config: { "base_tool_ids" => [ 1, 2 ] })

          patch :update, params: {
            project_id: @project.id,
            id: @workflow.id,
            workflow: { config: { inheritAllProjectResources: true } }
          }, as: :json

          assert_response :success
          @workflow.reload
          assert_equal [ 1, 2 ], @workflow.config["base_tool_ids"]
          assert_equal true, @workflow.config["inherit_all_project_resources"]
        end

        test "destroy soft-deletes workflow" do
          delete :destroy, params: { project_id: @project.id, id: @workflow.id }

          assert_response :no_content
        end
      end
    end
  end
end
