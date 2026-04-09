# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class WorkflowsControllerTest < ActionController::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :onboarding_completed, company: @company)
        @workflow = create(:workflow, scope: @company)
        sign_in @user
      end

      test "show returns workflow json" do
        get :show, params: { id: @workflow.id }

        assert_response :success
      end

      test "update returns workflow json" do
        patch :update, params: { id: @workflow.id, workflow: { name: "Renamed WF" } }

        assert_response :success
      end

      test "destroy soft-deletes workflow" do
        delete :destroy, params: { id: @workflow.id }

        assert_response :no_content
      end
    end
  end
end
