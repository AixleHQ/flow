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

        test "destroy soft-deletes workflow" do
          delete :destroy, params: { project_id: @project.id, id: @workflow.id }

          assert_response :no_content
        end
      end
    end
  end
end
