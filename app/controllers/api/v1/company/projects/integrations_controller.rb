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

            integration = if provider == "gitlab"
              Gitlab::IntegrationService.new(
                company: current_company,
                connected_by: current_user,
                project: current_project
              ).create(personal_access_token: params[:personal_access_token].to_s)
            else
              Github::IntegrationService.new(
                company: current_company,
                connected_by: current_user,
                project: current_project
              ).create(installation_id: params[:installation_id].to_s)
            end

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
