# frozen_string_literal: true

module Api
  module V1
    class SessionsController < Api::V1::ApplicationController
      skip_before_action :authenticate_user!, only: [ :create, :omniauth, :failure ]

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

      # @tags Authentication
      # @summary OAuth callback handler (Google)
      # @no_auth
      #
      # @response Successful OAuth login(302) [Redirect to root]
      # @response OAuth failed(302) [Redirect to login with error]
      def omniauth
        auth_service = GoogleOmniAuthService.new(request.env["omniauth.auth"])
        user = auth_service.authenticate

        if user.pending?
          redirect_to "/login?error=pending_approval", allow_other_host: false
          return
        end

        sign_in(user)
        redirect_to "/", allow_other_host: false
      rescue StandardError => e
        redirect_to "/login?error=oauth_failed", allow_other_host: false
      end

      def failure
        error_type = params[:message] || "oauth_failed"
        redirect_to "/login?error=#{error_type}", allow_other_host: false
      end

      private

      def user_sign_in_params
        params.require(:user).permit(:email, :password)
      end
    end
  end
end
