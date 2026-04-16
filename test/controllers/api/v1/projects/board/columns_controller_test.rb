# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Board
        class ColumnsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @col1 = create(:board_column, board: @board, name: "A")
            @col2 = create(:board_column, board: @board, name: "B")
            sign_in @user
          end

          test "index returns columns json" do
            get :index, params: { project_id: @project.id }

            assert_response :success
          end

          test "show returns column json" do
            get :show, params: { project_id: @project.id, id: @col1.id }

            assert_response :success
          end

          test "create returns column json" do
            post :create, params: {
              project_id: @project.id,
              board_column: { name: "Done", purpose: "done" }
            }

            assert_response :created
          end

          test "update returns column json" do
            patch :update, params: {
              project_id: @project.id,
              id: @col1.id,
              board_column: { name: "Renamed" }
            }

            assert_response :success
          end

          test "destroy removes column" do
            delete :destroy, params: { project_id: @project.id, id: @col1.id }

            assert_response :no_content
          end

          test "reorder returns columns json" do
            patch :reorder, params: {
              project_id: @project.id,
              column_ids: [ @col2.id, @col1.id ]
            }

            assert_response :success
          end
        end
      end
    end
  end
end
