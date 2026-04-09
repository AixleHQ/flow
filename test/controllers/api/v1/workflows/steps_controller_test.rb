# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Workflows
      class StepsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @workflow = create(:workflow, scope: @company)
          @step = create(:step, workflow: @workflow, position: 1)
          sign_in @user
        end

        test "index returns steps json" do
          get :index, params: { workflow_id: @workflow.id }

          assert_response :success
        end

        test "show returns step json" do
          get :show, params: { workflow_id: @workflow.id, id: @step.id }

          assert_response :success
        end

        test "create returns created step" do
          post :create, params: {
            workflow_id: @workflow.id,
            step: {
              name: "new_step",
              description: "D",
              instructions: "Do it",
              position: 2
            }
          }

          assert_response :created
        end

        test "update returns step json" do
          patch :update, params: {
            workflow_id: @workflow.id,
            id: @step.id,
            step: { description: "Updated" }
          }

          assert_response :success
        end

        test "destroy removes step" do
          delete :destroy, params: { workflow_id: @workflow.id, id: @step.id }

          assert_response :no_content
        end

        test "reorder returns ok" do
          s2 = create(:step, workflow: @workflow, position: 2)

          patch :reorder, params: {
            workflow_id: @workflow.id,
            positions: { @step.id.to_s => "1", s2.id.to_s => "2" }
          }

          assert_response :success
        end
      end
    end
  end
end
