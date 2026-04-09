# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      module Task
        class WaitsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @task = create(:board_task, board: @board, board_column: @column)
            @wait = TaskWait.create!(
              board_task: @task,
              creator: @user,
              wait_type: :github_checks_completed,
              status: :pending,
              metadata: {}
            )
            sign_in @user
          end

          test "destroy removes pending wait" do
            delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: @wait.id }

            assert_response :no_content
          end
        end
      end
    end
  end
  end
end
