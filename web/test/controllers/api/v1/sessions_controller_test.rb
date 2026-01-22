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

  private

  def current_user
    User.find_by(id: session[:user_id])
  end
end
