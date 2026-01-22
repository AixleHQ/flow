# frozen_string_literal: true

require "test_helper"

class Api::V1::CurrentUserControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    sign_in @user
  end

  test "#show returns success" do
    get :show

    assert_response :success
  end

  test "#show requires authentication" do
    sign_out

    get :show

    assert_response :unauthorized
  end

  test "#update with position and preferred_agent_language" do
    patch :update, params: {
      current_user: {
        position: "dev",
        preferred_agent_language: "en"
      }
    }

    assert_response :success
    @user.reload
    assert { @user.position == "dev" }
    assert { @user.preferred_agent_language == "en" }
  end

  test "#update with configured_agents sets onboarding_completed_at" do
    @user.update!(onboarding_completed_at: nil, position: nil, preferred_agent_language: nil)

    patch :update, params: {
      current_user: {
        position: "dev",
        preferred_agent_language: "en",
        configured_agents: [ "claude_code", "cursor_cli" ]
      }
    }

    assert_response :success
    @user.reload
    assert { @user.onboarding_completed_at.present? }
    assert { @user.configured_agents == [ "claude_code", "cursor_cli" ] }
  end

  test "#update with password and password_confirmation" do
    new_password = "newpassword123"

    patch :update, params: {
      current_user: {
        password: new_password,
        password_confirmation: new_password
      }
    }

    assert_response :success
    @user.reload
    assert { @user.authenticate(new_password) }
  end

  test "#update with name" do
    new_name = "Updated Name"

    patch :update, params: {
      current_user: { name: new_name }
    }

    assert_response :success
    @user.reload
    assert { @user.name == new_name }
  end

  test "#update requires authentication" do
    sign_out

    patch :update, params: {
      current_user: { name: "Hacker" }
    }

    assert_response :unauthorized
  end

  private

  def current_user
    User.find_by(id: session[:user_id])
  end
end
