# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Board
        class ViewPresetsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @board = create(:board, project: @project)
            @column = create(:board_column, board: @board)
            @preset = BoardViewPreset.create!(
              board: @board,
              user: @user,
              name: "Mine",
              filters: { "columns" => [ @column.id ] },
              shared: false
            )
            sign_in @user
          end

          test "index returns presets json" do
            get :index, params: { project_id: @project.id }

            assert_response :success
          end

          test "create returns preset json" do
            post :create, params: {
              project_id: @project.id,
              board_view_preset: {
                name: "New view",
                shared: false,
                filters: { "columns" => [ @column.id ] }
              }
            }

            assert_response :created
          end

          test "destroy removes own preset" do
            delete :destroy, params: { project_id: @project.id, id: @preset.id }

            assert_response :no_content
          end
        end
      end
    end
  end
end
