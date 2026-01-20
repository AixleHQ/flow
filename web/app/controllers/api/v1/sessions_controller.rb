# frozen_string_literal: true

module Api
  module V1
    class SessionsController < Api::V1::ApplicationController
      skip_before_action :authenticate_user!, only: [ :create ]

      # @tags Authentication
      # @summary Create a new user session (login)
      # @no_auth
      #
      # @request_body User login credentials [!Hash{user: {email: !String, password: !String}}]
      # @request_body_example Valid credentials [Hash] {user: {email: "user@example.com", password: "password123"}}
      #
      # @response Login successful(201) [Hash{}]
      # @response Invalid credentials(422) [Hash{errors: Hash{email: Array<String>, password: Array<String>}}]
      def create
        user_form = ::UserSignInForm.new(user_sign_in_params)
        if user_form.valid?
          user = user_form.user
          sign_in(user)

          head :created
        else
          respond_with user_form
        end
      end

      # @tags Authentication
      # @summary End current user session (logout)
      #
      # @response Logout successful(204) [Hash{}]
      def destroy
        sign_out
        head :no_content
      end

      private

      def user_sign_in_params
        params.require(:user).permit(:email, :password)
      end
    end
  end
end
