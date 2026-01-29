# frozen_string_literal: true

require "test_helper"

class Api::V1::SessionsControllerTest < ActionController::TestCase
  setup do
    @password = generate(:password)
    company = create(:company)
    @user = create(:user, password: @password, company: company)
  end

  test "#create" do
    auth_params = { user: { email: @user.email, password: @password } }
    post :create, params: auth_params

    assert_response :success
    assert { current_user.id == @user.id }
  end

  test "#create fails with invalid password" do
    auth_params = { user: { email: @user.email, password: "invalid_password" } }
    post :create, params: auth_params

    assert_response :unprocessable_entity
    assert { current_user.nil? }
  end

  test "#create with uppercase email" do
    auth_params = { user: { email: @user.email.upcase, password: @password } }
    post :create, params: auth_params

    assert_response :success
    assert { current_user.id == @user.id }
  end

  test "#destroy" do
    sign_in @user

    delete :destroy

    assert_response :success
    assert { current_user.nil? }
  end

  test "#create with admin user redirects to root" do
    company = create(:company)
    admin_user = create(:user, :admin, company: company, password: @password, onboarding_state: "completed")
    auth_params = { user: { email: admin_user.email, password: @password } }

    post :create, params: auth_params

    assert_response :success
    assert { current_user.id == admin_user.id }
  end

  test "#create with user without onboarding redirects to root" do
    company = create(:company)
    user = create(:user, :employee, company: company, password: @password, onboarding_state: "step1")
    auth_params = { user: { email: user.email, password: @password } }

    post :create, params: auth_params

    assert_response :success
    assert { current_user.id == user.id }
  end

  test "#create with pending user fails" do
    company = create(:company)
    pending_user = create(:user, :pending, company: company, password: @password)
    auth_params = { user: { email: pending_user.email, password: @password } }

    post :create, params: auth_params

    assert_response :unprocessable_entity
    assert { current_user.nil? }
  end

  test "#create with invalid password fails" do
    auth_params = { user: { email: @user.email, password: "wrong_password" } }

    post :create, params: auth_params

    assert_response :unprocessable_entity
    assert { current_user.nil? }
  end

  test "#create with non-existent email fails" do
    auth_params = { user: { email: "nonexistent@example.com", password: @password } }

    post :create, params: auth_params

    assert_response :unprocessable_entity
    assert { current_user.nil? }
  end

  test "#create with suspended user fails" do
    suspended_user = create(:user, company: create(:company), password: @password)
    suspended_user.suspend!
    auth_params = { user: { email: suspended_user.email, password: @password } }

    post :create, params: auth_params

    assert_response :unprocessable_entity
    assert { current_user.nil? }
  end

  test "#omniauth with auto_accept_users enabled creates active user" do
    company = create(:company, email_domain: "example.com", auto_accept_users: true)
    auth_hash = build_auth_hash(email: "newuser@example.com")
    @request.env["omniauth.auth"] = auth_hash

    assert_difference "User.count", 1 do
      process :omniauth, method: :get, params: { provider: "google" }
    end

    assert_redirected_to "/"
    user = User.find_by(email: "newuser@example.com")
    assert { user.present? }
    assert { user.active? }
    assert { user.company_id == company.id }
    assert { user.provider == "google" }
    assert { user.uid == "12345" }
    assert { user.google_token == "google_token_123" }
    assert { user.google_refresh_token == "refresh_token_123" }
    assert { user.avatar_url == "https://example.com/avatar.jpg" }
    assert { current_user.id == user.id }
  end

  test "#omniauth with auto_accept_users disabled creates pending user" do
    company = create(:company, email_domain: "example.com", auto_accept_users: false)
    auth_hash = build_auth_hash(email: "newuser@example.com")
    @request.env["omniauth.auth"] = auth_hash

    assert_difference "User.count", 1 do
      process :omniauth, method: :get, params: { provider: "google" }
    end

    assert_redirected_to "/login?error=pending_approval"
    user = User.find_by(email: "newuser@example.com")
    assert { user.present? }
    assert { user.pending? }
    assert { user.company_id == company.id }
    assert { current_user.nil? }
  end

  test "#omniauth with existing active user redirects to root" do
    company = create(:company, email_domain: "example.com", auto_accept_users: true)
    existing_user = create(:user, email: "existing@example.com", company: company, provider: "google", uid: "12345", onboarding_state: "completed")
    auth_hash = build_auth_hash(email: "existing@example.com")
    @request.env["omniauth.auth"] = auth_hash

    assert_no_difference "User.count" do
      process :omniauth, method: :get, params: { provider: "google" }
    end

    assert_redirected_to "/"
    assert { current_user.id == existing_user.id }
  end

  test "#omniauth with existing user without onboarding redirects to root" do
    company = create(:company, email_domain: "example.com", auto_accept_users: true)
    existing_user = create(:user, email: "existing@example.com", company: company, provider: "google", uid: "12345", onboarding_state: "step1")
    auth_hash = build_auth_hash(email: "existing@example.com")
    @request.env["omniauth.auth"] = auth_hash

    assert_no_difference "User.count" do
      process :omniauth, method: :get, params: { provider: "google" }
    end

    assert_redirected_to "/"
    assert { current_user.id == existing_user.id }
  end

  test "#omniauth with existing pending user redirects to login with error" do
    company = create(:company, email_domain: "example.com", auto_accept_users: false)
    existing_user = create(:user, :pending, email: "pending@example.com", company: company, provider: "google", uid: "12345")
    auth_hash = build_auth_hash(email: "pending@example.com")
    @request.env["omniauth.auth"] = auth_hash

    assert_no_difference "User.count" do
      process :omniauth, method: :get, params: { provider: "google" }
    end

    assert_redirected_to "/login?error=pending_approval"
    assert { current_user.nil? }
  end

  test "#omniauth without matching company redirects to login with error" do
    auth_hash = build_auth_hash(email: "nocompany@unknown.com")
    @request.env["omniauth.auth"] = auth_hash

    process :omniauth, method: :get, params: { provider: "google" }

    assert_redirected_to "/login?error=oauth_failed"
    assert { current_user.nil? }
  end

  test "#failure redirects to login with error message" do
    process :failure, method: :get, params: { message: "access_denied" }

    assert_redirected_to "/login?error=access_denied"
  end

  test "#failure without message redirects to login with default error" do
    process :failure, method: :get

    assert_redirected_to "/login?error=oauth_failed"
  end

  private

  def current_user
    User.find_by(id: session[:user_id])
  end

  def build_auth_hash(email: "test@example.com", uid: "12345", name: "Test User")
    OmniAuth::AuthHash.new(
      {
        "provider" => "google",
        "uid" => uid,
        "info" => {
          "email" => email,
          "name" => name,
          "image" => "https://example.com/avatar.jpg"
        },
        "credentials" => {
          "token" => "google_token_123",
          "refresh_token" => "refresh_token_123"
        }
      }
    )
  end
end
