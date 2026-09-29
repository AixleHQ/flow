# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      module Task
        class AssetsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @task = create(:board_task, board: @board, board_column: @column)
            @asset = create(:task_asset, board_task: @task, author: @user)
            sign_in @user
          end

          test "index returns assets json" do
            get :index, params: { project_id: @project.id, task_id: @task.id }

            assert_response :success
          end

          test "create returns asset json" do
            post :create, params: {
              project_id: @project.id,
              task_id: @task.id,
              task_asset: { name: "notes.md" }
            }

            assert_response :created
          end

          test "destroy removes asset" do
            delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: @asset.id }

            assert_response :no_content
          end

          test "unshare stops a public link working" do
            token = @asset.share!

            delete :unshare, params: { project_id: @project.id, task_id: @task.id, id: @asset.id }

            assert_response :success
            assert_nil response.parsed_body["shareUrl"]
            assert_nil PubliclyShareable.find_shared(token)
          end
        end
      end
    end
  end
  end
end
