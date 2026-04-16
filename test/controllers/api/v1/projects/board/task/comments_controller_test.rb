# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      module Task
        class CommentsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @task = create(:board_task, board: @board, board_column: @column)
            create(:task_comment, board_task: @task, author: @user)
            sign_in @user
          end

          test "index returns comments json" do
            get :index, params: { project_id: @project.id, task_id: @task.id }

            assert_response :success
          end

          test "create returns comment json" do
            post :create, params: {
              project_id: @project.id,
              task_id: @task.id,
              task_comment: { body: "Hello" }
            }

            assert_response :created
          end
        end
      end
    end
  end
  end
end
