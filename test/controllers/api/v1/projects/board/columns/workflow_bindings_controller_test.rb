# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Board
        module Columns
          class WorkflowBindingsControllerTest < ActionController::TestCase
            setup do
              @company = create(:company)
              @user = create(:user, :onboarding_completed, company: @company)
              @project = create(:project, company: @company, owner: @user)
              @board = create(:board, project: @project)
              @column = create(:board_column, board: @board)
              @workflow = create(:workflow, scope: @company)
              sign_in @user
            end

            test "show returns not_found without binding" do
              get :show, params: { project_id: @project.id, column_id: @column.id }

              assert_response :not_found
            end

            test "create returns binding json" do
              post :create, params: {
                project_id: @project.id,
                column_id: @column.id,
                column_workflow_binding: {
                  workflow_id: @workflow.id,
                  trigger_mode: "manual",
                  cooldown_seconds: 0
                }
              }

              assert_response :created
            end

            test "update returns binding json" do
              binding = ColumnWorkflowBinding.create!(
                board_column: @column,
                workflow: @workflow,
                trigger_mode: :manual,
                cooldown_seconds: 0
              )

              patch :update, params: {
                project_id: @project.id,
                column_id: @column.id,
                column_workflow_binding: { cooldown_seconds: 30 }
              }

              assert_response :success
            end

            test "destroy removes binding" do
              ColumnWorkflowBinding.create!(
                board_column: @column,
                workflow: @workflow,
                trigger_mode: :manual,
                cooldown_seconds: 0
              )

              delete :destroy, params: { project_id: @project.id, column_id: @column.id }

              assert_response :no_content
            end
          end
        end
      end
    end
  end
end
