# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      class BoardControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          sign_in @user
        end

        test "create returns board json" do
          post :create, params: { project_id: @project.id, board: { name: "Main" } }

          assert_response :created
        end

        test "update returns board json" do
          board = create(:board, project: @project)

          patch :update, params: { project_id: @project.id, board: { name: "Renamed" } }

          assert_response :success
        end

        test "destroy removes board" do
          create(:board, project: @project)

          delete :destroy, params: { project_id: @project.id }

          assert_response :no_content
        end
      end
    end
  end
end
