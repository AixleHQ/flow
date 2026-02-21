# frozen_string_literal: true

require "test_helper"

module Admin
  class AgentCredentialsControllerTest < Admin::ActionControllerTestCase
    setup do
      @user = create(:user, :with_company)
      @credential = create(:agent_credential, user: @user)
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

    # Credentials are created via auth flow; admin create requires encrypted_config_data
    test "should not create agent_credential without encrypted_config_data" do
      assert_no_difference("AgentCredential.count") do
        post :create, params: {
          agent_credential: {
            user_id: @user.id,
            agent_type: "cursor_cli",
            expires_at: 1.day.from_now
          }
        }
      end

      assert_response :unprocessable_entity
    end

    test "should show agent_credential" do
      get :show, params: { id: @credential.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @credential.id }
      assert_response :success
    end

    test "should update agent_credential" do
      patch :update, params: {
        id: @credential.id,
        agent_credential: { expires_at: 2.days.from_now }
      }

      assert_redirected_to admin_agent_credential_path(@credential)
    end

    test "should destroy agent_credential" do
      assert_difference("AgentCredential.count", -1) do
        delete :destroy, params: { id: @credential.id }
      end

      assert_redirected_to admin_agent_credentials_path
    end
  end
end
