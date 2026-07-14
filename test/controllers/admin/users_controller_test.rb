# frozen_string_literal: true

require "test_helper"

module Admin
  class UsersControllerTest < Admin::ActionControllerTestCase
    setup do
      @user = create(:user, :with_company)
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should get new" do
      get :new
      assert_response :success
    end

    test "should create user" do
      company = create(:company, email_domain: "testcompany.com")

      assert_difference("User.count") do
        post :create, params: {
          user: {
            email: "newuser@testcompany.com",
            name: "New User",
            password: "password123",
            password_confirmation: "password123",
            company_id: company.id,
            role: "employee"
          }
        }
      end

      assert_redirected_to admin_user_path(User.last)
    end

    test "should show user" do
      get :show, params: { id: @user.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @user.id }
      assert_response :success
    end

    test "should update user" do
      patch :update, params: {
        id: @user.id,
        user: {
          name: "Updated Name"
        }
      }

      assert_redirected_to admin_user_path(@user)
    end

    test "should soft delete user" do
      # Soft delete: the row is kept (count unchanged) but marked deleted.
      assert_no_difference("User.count") do
        delete :destroy, params: { id: @user.id }
      end

      assert @user.reload.deleted?
      assert_redirected_to admin_root_path
    end

    test "should soft delete user who has board activities without FK violation" do
      # Regression for the Sentry FK violation on board_activities.actor_id:
      # deleting a user who authored board activities must not raise and must
      # preserve those activities.
      project = create(:project, company: @user.company, owner: @user)
      board = create(:board, project: project)
      activity = BoardActivity.create!(
        board: board, event_type: :task_created, actor: @user, actor_type: :human
      )

      assert_no_difference(["User.count", "BoardActivity.count"]) do
        delete :destroy, params: { id: @user.id }
      end

      assert @user.reload.deleted?
      assert_equal @user.id, activity.reload.actor_id
      assert_redirected_to admin_root_path
    end

    test "should not destroy super_admin user" do
      assert_no_difference("User.count") do
        delete :destroy, params: { id: @super_admin.id }
      end

      assert_not @super_admin.reload.deleted?
      assert_redirected_to admin_users_path
    end

    test "should impersonate user" do
      post :impersonate, params: { id: @user.id }

      assert_equal @user.id, session[:user_id]
      assert_equal @super_admin.id, session["true_user_id"]
      assert_redirected_to root_path
    end

    test "should stop impersonating user" do
      # First impersonate
      post :impersonate, params: { id: @user.id }
      assert_equal @user.id, session[:user_id]

      # Then stop impersonating
      post :stop_impersonate, params: { id: @user.id }

      assert_equal @super_admin.id, session[:user_id]
      assert_nil session["true_user_id"]
      assert_redirected_to admin_users_path
    end
  end
end
