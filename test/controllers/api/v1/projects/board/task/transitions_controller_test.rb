# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      module Task
        class TransitionsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @col1 = create(:board_column, board: @board)
            @col2 = create(:board_column, board: @board)
            @task = create(:board_task, board: @board, board_column: @col2)
            ColumnTransition.create!(
              board_task: @task,
              from_column: @col1,
              to_column: @col2,
              actor: @user,
              actor_type: :human
            )
            sign_in @user
          end

          test "index returns transitions json" do
            get :index, params: { project_id: @project.id, task_id: @task.id }

            assert_response :success
          end
        end
      end
    end
  end
  end
end
