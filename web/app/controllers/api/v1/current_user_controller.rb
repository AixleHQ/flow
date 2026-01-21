# frozen_string_literal: true

module Api
  module V1
    class CurrentUserController < Api::V1::ApplicationController
      # @tags User
      # @summary Get current user info
      #
      # @response Current user data(200) [Hash{user: Hash}]
      def show
        render json: {
          user: user_data,
          company: company_data
        }
      end

      private

      def user_data
        {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          onboarding_completed: current_user.onboarding_completed?,
          selected_agents: current_user.selected_agents,
          configured_agents: current_user.configured_agents,
          pending_agents: current_user.pending_agents
        }
      end

      def company_data
        company = current_user.company
        {
          id: company.id,
          name: company.name,
          slug: company.slug,
          branding: company.branding
        }
      end
    end
  end
end
