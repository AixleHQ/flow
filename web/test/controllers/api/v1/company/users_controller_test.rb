# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::UsersControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_user = create(:user, :employee, company: @other_company)
  end

  # ====== INDEX Tests ======

  test "#index returns company users for admin" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 2 }
    user_ids = json["items"].map { |u| u["id"] }
    assert { user_ids.include?(@admin.id) }
    assert { user_ids.include?(@employee.id) }
    refute { user_ids.include?(@other_user.id) }
  end

  test "#index with role filter" do
    sign_in @admin

    get :index, params: { q: { role_eq: "admin" } }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["id"] == @admin.id }
  end

  test "#index with state filter" do
    pending_user = create(:user, :employee, :pending, company: @company)
    sign_in @admin

    get :index, params: { q: { state_eq: "pending" } }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["id"] == pending_user.id }
  end

  test "#index with email search" do
    sign_in @admin

    get :index, params: { q: { email_cont: @employee.email.split("@").first } }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length >= 1 }
    assert { json["items"].any? { |u| u["id"] == @employee.id } }
  end

  test "#index with name search" do
    @employee.update!(name: "John Unique Name")
    sign_in @admin

    get :index, params: { q: { name_cont: "Unique" } }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["id"] == @employee.id }
  end

  test "#index requires admin role" do
    sign_in @employee

    get :index

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index

    assert_response :unauthorized
  end

  # ====== CREATE (Invite) Tests ======

  test "#create invites new user with active state" do
    sign_in @admin

    assert_difference("User.count") do
      post :create, params: {
        user: {
          email: "newuser@testcompany.com",
          name: "New User",
          role: "employee"
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    new_user = User.find(json["data"]["id"])
    assert { new_user.email == "newuser@testcompany.com" }
    assert { new_user.name == "New User" }
    assert { new_user.role == "employee" }
    assert { new_user.state == "active" }
    assert { new_user.invited_by_id == @admin.id }
    assert { new_user.invited_at.present? }
    assert { new_user.company_id == @company.id }
  end

  test "#create with admin role" do
    sign_in @admin

    post :create, params: {
      user: {
        email: "newadmin@testcompany.com",
        name: "New Admin",
        role: "admin"
      }
    }

    assert_response :created
    json = response.parsed_body
    new_user = User.find(json["data"]["id"])
    assert { new_user.role == "admin" }
  end

  test "#create cannot assign super_admin role" do
    sign_in @admin

    post :create, params: {
      user: {
        email: "hacker@testcompany.com",
        name: "Hacker",
        role: "super_admin"
      }
    }

    assert_response :created
    json = response.parsed_body
    new_user = User.find(json["data"]["id"])
    assert { new_user.role == "employee" } # should default to employee, not super_admin
  end

  test "#create with wrong email domain fails" do
    sign_in @admin

    assert_no_difference("User.count") do
      post :create, params: {
        user: {
          email: "newuser@wrongdomain.com",
          name: "New User",
          role: "employee"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["email"].present? }
  end

  test "#create with existing email fails" do
    sign_in @admin

    assert_no_difference("User.count") do
      post :create, params: {
        user: {
          email: @employee.email,
          name: "Duplicate User",
          role: "employee"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["email"].present? }
  end

  test "#create requires admin role" do
    sign_in @employee

    assert_no_difference("User.count") do
      post :create, params: {
        user: {
          email: "newuser@testcompany.com",
          name: "New User",
          role: "employee"
        }
      }
    end

    assert_response :forbidden
  end

  test "#create requires authentication" do
    assert_no_difference("User.count") do
      post :create, params: {
        user: {
          email: "newuser@testcompany.com",
          name: "New User",
          role: "employee"
        }
      }
    end

    assert_response :unauthorized
  end

  # ====== UPDATE (State Change) Tests ======

  test "#update archives user" do
    sign_in @admin

    patch :update, params: {
      id: @employee.id,
      user: { state_event: "archive" }
    }

    assert_response :success
    @employee.reload
    assert { @employee.state == "archived" }
  end

  test "#update activates archived user" do
    @employee.archive!
    sign_in @admin

    patch :update, params: {
      id: @employee.id,
      user: { state_event: "activate" }
    }

    assert_response :success
    @employee.reload
    assert { @employee.state == "active" }
  end

  test "#update changes user role" do
    sign_in @admin

    patch :update, params: {
      id: @employee.id,
      user: { role: "admin" }
    }

    assert_response :success
    @employee.reload
    assert { @employee.role == "admin" }
  end

  test "#update cannot assign super_admin role" do
    sign_in @admin

    patch :update, params: {
      id: @employee.id,
      user: { role: "super_admin" }
    }

    assert_response :success
    @employee.reload
    assert { @employee.role == "employee" } # role should not change
  end

  test "#update cannot modify user from another company" do
    sign_in @admin

    patch :update, params: {
      id: @other_user.id,
      user: { state_event: "archive" }
    }

    assert_response :not_found
  end

  test "#update requires admin role" do
    sign_in @employee

    patch :update, params: {
      id: @admin.id,
      user: { state_event: "archive" }
    }

    assert_response :forbidden
  end

  test "#update requires authentication" do
    patch :update, params: {
      id: @employee.id,
      user: { state_event: "archive" }
    }

    assert_response :unauthorized
  end

  # ====== Pagination Tests ======

  test "#index returns pagination metadata" do
    # Create more users to test pagination
    10.times do |i|
      create(:user, :employee, company: @company)
    end
    sign_in @admin

    get :index, params: { page: 1, per_page: 5 }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 5 }
    assert { json["meta"]["page"] == 1 }
    assert { json["meta"]["total_count"] == 12 } # 2 original + 10 new
  end

  # ====== Response Format Tests ======

  test "#index returns expected user fields" do
    @employee.update!(position: "dev", invited_by: @admin, invited_at: 1.day.ago)
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    employee_data = json["items"].find { |u| u["id"] == @employee.id }
    assert { employee_data["email"].present? }
    assert { employee_data["name"].present? }
    assert { employee_data["role"].present? }
    assert { employee_data["state"].present? }
    assert { employee_data["position"] == "dev" }
    assert { employee_data["invited_at"].present? }
    assert { employee_data["invited_by"]["id"] == @admin.id }
    assert { employee_data["invited_by"]["name"] == @admin.name }
  end
end
