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
            assert_equal [ @col2.id, @col1.id ], @board.board_columns.reload.order(:position).map(&:id)
          end

          # The board settings dialog omits any column that appeared while it was
          # open. Renumbering only the named ones then collided with the ones it
          # did not name, on the (board_id, position) unique index.
          test "reorder with a partial list still lands on one position per column" do
            col3 = create(:board_column, board: @board, name: "C")

            patch :reorder, params: { project_id: @project.id, column_ids: [ col3.id, @col1.id ] }

            assert_response :success
            ordered = @board.board_columns.reload.order(:position)
            assert_equal [ col3.id, @col1.id, @col2.id ], ordered.map(&:id)
            assert_equal [ 1, 2, 3 ], ordered.map(&:position)
          end

          # A column someone else deleted mid-drag, or a repeated id, is a stale
          # payload — not a reason to leave the board's numbering half-written.
          test "reorder ignores unknown and repeated ids" do
            patch :reorder, params: {
              project_id: @project.id,
              column_ids: [ @col2.id, @col2.id, 999_999, @col1.id ]
            }

            assert_response :success
            ordered = @board.board_columns.reload.order(:position)
            assert_equal [ @col2.id, @col1.id ], ordered.map(&:id)
            assert_equal [ 1, 2 ], ordered.map(&:position)
          end
        end
      end
    end
  end
end
