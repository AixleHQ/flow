# frozen_string_literal: true

require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "super_admin can access admin dashboard" do
      super_admin = create(:user, :super_admin)
      sign_in_as(super_admin)

      get "/admin", as: :json

      assert_response :success
      json_response = JSON.parse(response.body)
      assert_equal "Admin Dashboard", json_response["message"]
      assert_equal super_admin.email, json_response["user"]
    end

    test "super_admin can access admin dashboard via dashboard path" do
      super_admin = create(:user, :super_admin)
      sign_in_as(super_admin)

      get "/admin/dashboard", as: :json

      assert_response :success
      json_response = JSON.parse(response.body)
      assert_equal "Admin Dashboard", json_response["message"]
    end

    test "regular user cannot access admin dashboard" do
      regular_user = create(:user, :collaborator)
      sign_in_as(regular_user)

      get "/admin"

      assert_redirected_to "/login"
    end

    test "admin role user cannot access admin dashboard" do
      admin_user = create(:user, :admin_role)
      sign_in_as(admin_user)

      get "/admin"

      assert_redirected_to "/login"
    end

    test "unauthenticated user cannot access admin dashboard" do
      get "/admin"

      assert_redirected_to "/login"
    end
  end
end
