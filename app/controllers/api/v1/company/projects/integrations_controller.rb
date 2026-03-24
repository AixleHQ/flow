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
            provider = params[:provider].to_s

            if provider == "gitlab"
              create_gitlab_integration
            else
              create_github_integration
            end
          end

          def destroy
            integration = Integration.for_project(current_project).find(params[:id])
            integration.destroy
            respond_with integration
          end

          private

          def create_gitlab_integration
            integration = Integration.find_or_build_gitlab_for_token(
              company: current_company,
              connected_by: current_user,
              project: current_project
            )
            integration.credentials_data = { personal_access_token: params[:personal_access_token].to_s }

            begin
              info = Gitlab::TokenService.new(integration).verify_token
              integration.name = info[:username]
              integration.status = :active
            rescue Gitlab::TokenService::ConfigurationError, Gitlab::TokenService::AuthenticationError => e
              integration.name = "GitLab (unverified)" if integration.name.blank?
              integration.status = :error
              integration.settings = { error: e.message }
            end

            integration.save
            respond_with integration, serializer: IntegrationSerializer
          end

          def create_github_integration
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
        end
      end
    end
  end
end
