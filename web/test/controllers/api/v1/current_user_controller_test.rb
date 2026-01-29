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

  # ====== Story 1.3: Profile Update Validation Tests ======

  test "#update with empty name fails validation" do
    patch :update, params: {
      current_user: { name: "" }
    }

    assert_response :unprocessable_entity
    @user.reload
    # Name should not be changed
    assert { @user.name.present? }
  end

  test "#update cannot change email (not permitted)" do
    original_email = @user.email

    patch :update, params: {
      current_user: { email: "hacker@evil.com" }
    }

    # Request succeeds (unpermitted params are silently ignored)
    assert_response :success
    @user.reload
    # Email should remain unchanged
    assert { @user.email == original_email }
  end

  test "#update cannot change role (not permitted)" do
    original_role = @user.role

    patch :update, params: {
      current_user: { role: "super_admin" }
    }

    # Request succeeds (unpermitted params are silently ignored)
    assert_response :success
    @user.reload
    # Role should remain unchanged
    assert { @user.role == original_role }
  end

  test "#update cannot change company_id (not permitted)" do
    other_company = create(:company, name: "Other Company")
    original_company_id = @user.company_id

    patch :update, params: {
      current_user: { company_id: other_company.id }
    }

    # Request succeeds (unpermitted params are silently ignored)
    assert_response :success
    @user.reload
    # Company should remain unchanged
    assert { @user.company_id == original_company_id }
  end

  test "#show returns configured_agents from agent_credentials" do
    create(:agent_credential, user: @user, agent_type: "claude_code")
    create(:agent_credential, user: @user, agent_type: "cursor_cli")

    get :show

    assert_response :success
    json = response.parsed_body
    # configured_agents is derived from agent_credentials
    assert { json["data"]["configured_agents"].sort == %w[claude_code cursor_cli] }
  end

  test "#show returns agent_credentials list" do
    create(:agent_credential, user: @user, agent_type: "claude_code")
    create(:agent_credential, user: @user, agent_type: "cursor_cli")

    get :show

    assert_response :success
    json = response.parsed_body
    credentials = json["data"]["agent_credentials"]
    assert { credentials.length == 2 }
    assert { credentials.map { |c| c["agent_type"] }.sort == %w[claude_code cursor_cli] }
    # Should not expose encrypted data
    assert { credentials.all? { |c| c["encrypted_config_data"].nil? } }
  end

  # ====== Story 2.7: Onboarding State Machine Tests ======

  test "#update with selected_agents saves array" do
    patch :update, params: {
      current_user: {
        selected_agents: %w[claude_code cursor_cli]
      }
    }

    assert_response :success
    @user.reload
    assert { @user.selected_agents == %w[claude_code cursor_cli] }
  end

  test "#show returns selected_agents and onboarding_state" do
    @user.update!(selected_agents: %w[claude_code codex])

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json["data"]["selected_agents"] == %w[claude_code codex] }
    assert { json["data"]["onboarding_state"] == "step1" }
  end

  test "#update rejects invalid selected_agents values" do
    patch :update, params: {
      current_user: {
        selected_agents: %w[claude_code invalid_agent]
      }
    }

    assert_response :unprocessable_entity
  end

  # ====== Onboarding State Event Tests (via update) ======

  test "#update with onboarding_state_event go_next transitions from step1 to step2" do
    @user.update!(onboarding_state: "step1")

    patch :update, params: { current_user: { onboarding_state_event: "go_next" } }

    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step2" }
  end

  test "#update with onboarding_state_event go_next transitions from step2 to step3" do
    @user.update!(onboarding_state: "step2")

    patch :update, params: { current_user: { onboarding_state_event: "go_next" } }

    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step3" }
  end

  test "#update with onboarding_state_event go_next transitions from step3 to step4" do
    @user.update!(onboarding_state: "step3")

    patch :update, params: { current_user: { onboarding_state_event: "go_next" } }

    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step4" }
  end

  test "#update with onboarding_state_event go_next ignores invalid transition from step4" do
    @user.update!(onboarding_state: "step4")

    patch :update, params: { current_user: { onboarding_state_event: "go_next" } }

    # StateEventConcern silently ignores invalid transitions
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step4" }
  end

  test "#update with onboarding_state_event go_previous transitions from step2 to step1" do
    @user.update!(onboarding_state: "step2")

    patch :update, params: { current_user: { onboarding_state_event: "go_previous" } }

    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step1" }
  end

  test "#update with onboarding_state_event go_previous ignores invalid transition from step1" do
    @user.update!(onboarding_state: "step1")

    patch :update, params: { current_user: { onboarding_state_event: "go_previous" } }

    # StateEventConcern silently ignores invalid transitions
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step1" }
  end

  test "#update with onboarding_state_event complete transitions from step4 to completed when requirements met" do
    @user.update!(
      onboarding_state: "step4",
      position: "dev",
      preferred_agent_language: "en"
    )
    create(:agent_credential, user: @user, agent_type: "claude_code")

    patch :update, params: { current_user: { onboarding_state_event: "complete" } }

    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "completed" }
    assert { @user.onboarding_completed_at.present? }
  end

  test "#update with onboarding_state_event complete ignores when position missing" do
    @user.update!(
      onboarding_state: "step4",
      position: nil,
      preferred_agent_language: "en"
    )
    create(:agent_credential, user: @user, agent_type: "claude_code")

    patch :update, params: { current_user: { onboarding_state_event: "complete" } }

    # Guard fails, transition silently ignored
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step4" }
  end

  test "#update with onboarding_state_event complete ignores when language missing" do
    @user.update!(
      onboarding_state: "step4",
      position: "dev",
      preferred_agent_language: nil
    )
    create(:agent_credential, user: @user, agent_type: "claude_code")

    patch :update, params: { current_user: { onboarding_state_event: "complete" } }

    # Guard fails, transition silently ignored
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step4" }
  end

  test "#update with onboarding_state_event complete ignores when no agent_credentials" do
    @user.update!(
      onboarding_state: "step4",
      position: "dev",
      preferred_agent_language: "en"
    )
    # No agent credentials

    patch :update, params: { current_user: { onboarding_state_event: "complete" } }

    # Guard fails, transition silently ignored
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step4" }
  end

  test "#update with invalid onboarding_state_event is silently ignored" do
    @user.update!(onboarding_state: "step1")

    patch :update, params: { current_user: { onboarding_state_event: "invalid_event" } }

    # Invalid events are silently ignored by StateEventConcern
    assert_response :success
    @user.reload
    assert { @user.onboarding_state == "step1" }
  end

  private

  def current_user
    User.find_by(id: session[:user_id])
  end
end
