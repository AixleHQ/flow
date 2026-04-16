# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Workflows
        class StepsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @workflow = create(:workflow, scope: @project)
            @step = create(:step, workflow: @workflow, position: 1)
            sign_in @user
          end

          test "index returns steps json" do
            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }

            assert_response :success
          end

          test "show returns step json" do
            get :show, params: { project_id: @project.id, workflow_id: @workflow.id, id: @step.id }

            assert_response :success
          end

          test "create returns created step" do
            post :create, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              step: {
                name: "p_step",
                description: "D",
                instructions: "Run",
                position: 2
              }
            }

            assert_response :created
          end

          test "update returns step json" do
            patch :update, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              id: @step.id,
              step: { description: "U" }
            }

            assert_response :success
          end

          test "destroy removes step" do
            delete :destroy, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              id: @step.id
            }

            assert_response :no_content
          end

          test "reorder returns ok" do
            s2 = create(:step, workflow: @workflow, position: 2)

            patch :reorder, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              positions: { @step.id.to_s => "1", s2.id.to_s => "2" }
            }

            assert_response :success
          end
        end
      end
    end
  end
end
