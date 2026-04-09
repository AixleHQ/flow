# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Board
        class ActivitiesControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @task = create(:board_task, board: @board, board_column: @column)
            BoardActivity.create!(
              board: @board,
              board_task: @task,
              actor: @user,
              event_type: :task_created,
              actor_type: :human
            )
            sign_in @user
          end

          test "index returns paginated activities json" do
            get :index, params: { project_id: @project.id }

            assert_response :success
          end
        end
      end
    end
  end
end
