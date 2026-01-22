# frozen_string_literal: true

class Api::V1::CurrentUserController < Api::V1::ApplicationController
  # @tags CurrentUser
  # @summary Get the current user
  #
  # @response Success(200) [User]
  # @response_example Success(200) [Hash] [{"id": "1", "name": "John Doe", "email": "john.doe@example.com", "new_user": true, "permissions": [{"id": 1, "resourceType": "Workspace", "resourceId": 1, "resourceName": "Workspace 1", "name": "write", "parents": [{"id": 1, "resourceType": "Account", "resourceId": 1, "resourceName": "Account 1"}]}]}]

  def show
    respond_with current_user, serializer: CurrentUserSerializer
  end

  # @tags CurrentUser
  # @summary Update the current user
  #
  # @request_body
  #   [ !Hash{ current_user: Hash{ password: String, password_confirmation: String, name: String } } ]
  #
  # @response Success(200) [User]
  # @response_example Success(200) [Hash] [{"id": "1", "name": "John Doe", "email": "john.doe@example.com", "new_user": false, "permissions": [{"id": 1, "resourceType": "Workspace", "resourceId": 1, "resourceName": "Workspace 1", "name": "write", "parents": [{"id": 1, "resourceType": "Account", "resourceId": 1, "resourceName": "Account 1"}]}]}]
  def update
    current_user.update(update_current_user_params)
    respond_with current_user, serializer: CurrentUserSerializer
  end

  private

  def update_current_user_params
    params.require(:current_user).permit(:password, :password_confirmation, :name)
  end
end
