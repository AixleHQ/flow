# frozen_string_literal: true

class Api::V1::CurrentUserController < Api::V1::ApplicationController
  # @tags CurrentUser
  # @summary Get the current user
  #
  # @response Success(200) [User]
  # @response_example Success(200) [Hash] [{"id": "1", "name": "John Doe", "email": "john.doe@example.com"}]
  def show
    respond_with current_user, serializer: CurrentUserSerializer
  end

  # @tags CurrentUser
  # @summary Update the current user
  # Note: configured_agents is read-only, derived from AgentCredentials
  # Use onboarding_state_event to trigger state transitions: go_next, go_previous, complete
  #
  # @request_body
  #   [ !Hash{ current_user: Hash{ password: String, password_confirmation: String, name: String, position: String, preferred_agent_language: String, selected_agents: Array, onboarding_state_event: String } } ]
  #
  # @response Success(200) [User]
  def update
    current_user.update(update_current_user_params)
    respond_with current_user, serializer: CurrentUserSerializer
  end

  private

  def update_current_user_params
    params.require(:current_user).permit(
      :password, :password_confirmation, :name,
      :position, :preferred_agent_language,
      :onboarding_state_event,
      selected_agents: []
    )
  end
end
