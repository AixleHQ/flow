# frozen_string_literal: true

module Api
  module V1
    module Company
      class IntegrationsController < ApplicationController
        skip_before_action :dynamic_authorize!, only: :github_setup

        def github_setup
          installation_id = params[:installation_id]
          if installation_id.blank?
            redirect_to "/company/integrations"
            return
          end

          existing = current_company.integrations.where(provider: :github).find do |i|
            i.installation_id == installation_id.to_s
          end

          integration = existing || current_company.integrations.new(
            provider: :github,
            connected_by: current_user
          )
          integration.credentials_data = { installation_id: installation_id.to_s }

          begin
            info = Github::TokenService.new(integration).verify_installation
            integration.name = info[:account_login]
            integration.settings = {
              account_type: info[:account_type],
              target_type: info[:target_type]
            }
            integration.status = :active
          rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
            integration.name ||= "GitHub (unverified)"
            integration.status = :error
            integration.settings = { error: e.message }
          end

          integration.save
          redirect_to "/company/integrations"
        end

        def index
          integrations = current_company.integrations.ransack(params[:q]).result
          respond_with integrations, each_serializer: IntegrationSerializer
        end

        def show
          integration = current_company.integrations.find(params[:id])
          respond_with integration, serializer: IntegrationSerializer
        end

        def create
          integration = current_company.integrations.new(
            provider: :github,
            connected_by: current_user,
            status: :inactive
          )
          integration.credentials_data = { installation_id: params[:installation_id].to_s }

          begin
            info = Github::TokenService.new(integration).verify_installation
            integration.name = info[:account_login]
            integration.settings = {
              account_type: info[:account_type],
              target_type: info[:target_type]
            }
            integration.status = :active
          rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
            integration.name = "GitHub (unverified)" if integration.name.blank?
            integration.status = :error
            integration.settings = { error: e.message }
          end

          integration.save
          respond_with integration, serializer: IntegrationSerializer
        end

        def destroy
          integration = current_company.integrations.find(params[:id])
          integration.destroy
          respond_with integration
        end
      end
    end
  end
end
