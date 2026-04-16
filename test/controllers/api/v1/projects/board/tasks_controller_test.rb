# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      class TasksControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          @board = create(:board, project: @project)
          @col1 = create(:board_column, board: @board, name: "Todo")
          @col2 = create(:board_column, board: @board, name: "Done")
          @task = create(:board_task, board: @board, board_column: @col1)
          @workflow = create(:workflow, scope: @company)
          sign_in @user
        end

        test "index returns tasks json" do
          get :index, params: { project_id: @project.id }

          assert_response :success
        end

        test "show returns task json" do
          get :show, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        test "create returns task json" do
          post :create, params: {
            project_id: @project.id,
            board_task: { title: "New task", board_column_id: @col1.id }
          }

          assert_response :created
        end

        test "update returns task json" do
          patch :update, params: {
            project_id: @project.id,
            id: @task.id,
            board_task: { title: "Updated" }
          }

          assert_response :success
        end

        test "destroy removes task" do
          delete :destroy, params: { project_id: @project.id, id: @task.id }

          assert_response :no_content
        end

        test "move returns task json" do
          patch :move, params: {
            project_id: @project.id,
            id: @task.id,
            column_id: @col2.id
          }

          assert_response :success
        end

        test "workflow_runs returns runs json" do
          create(:workflow_run, workflow: @workflow, project: @project, user: @user, board_task: @task)

          get :workflow_runs, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        test "trigger_workflow returns run json when service succeeds" do
          ColumnWorkflowBinding.create!(
            board_column: @col1,
            workflow: @workflow,
            trigger_mode: :manual,
            cooldown_seconds: 0
          )
          run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: @task)
          TaskService.stubs(:trigger_workflow).returns(run)

          post :trigger_workflow, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end
      end
    end
  end
  end
end
