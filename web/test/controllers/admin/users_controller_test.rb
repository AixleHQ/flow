# frozen_string_literal: true

require "test_helper"

module Admin
  class UsersControllerTest < Admin::ActionControllerTestCase
    setup do
      @user = create(:user, :collaborator)
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
      company = create(:company)

      assert_difference("User.count") do
        post :create, params: {
          user: attributes_for(:user, :collaborator).merge(
            company_id: company.id
          )
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
          email: generate(:email)
        }
      }

      assert_redirected_to admin_user_path(@user)
    end

    test "should destroy user" do
      assert_difference("User.count", -1) do
        delete :destroy, params: { id: @user.id }
      end

      assert_redirected_to admin_root_path
    end

    test "should not destroy super_admin user" do
      assert_no_difference("User.count") do
        delete :destroy, params: { id: @super_admin.id }
      end

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
