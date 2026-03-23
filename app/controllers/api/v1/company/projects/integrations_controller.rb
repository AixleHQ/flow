# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class IntegrationsController < Projects::ApplicationController
          def index
            list = Integration.visible_for_project(current_project).includes(:connected_by).order(:provider, :name)
            respond_with list, each_serializer: IntegrationSerializer
          end

          def create
            integration = current_company.integrations.new(
              provider: :github,
              connected_by: current_user,
              status: :inactive,
              project: current_project
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
            integration = Integration.for_project(current_project).find(params[:id])
            integration.destroy
            respond_with integration
          end
        end
      end
    end
  end
end
