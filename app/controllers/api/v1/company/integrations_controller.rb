# frozen_string_literal: true

module Api
  module V1
    module Company
      class IntegrationsController < ApplicationController
        skip_before_action :dynamic_authorize!, only: :github_setup

        def github_setup
          target_project = resolve_github_setup_project(params[:state])
          installation_id = params[:installation_id]

          if installation_id.blank?
            redirect_to github_setup_redirect_path(target_project)
            return
          end

          if target_project.present? && !target_project.accessible_by?(current_user)
            redirect_to "/company/integrations"
            return
          end

          integration = Integration.find_or_build_github_for_installation(
            company: current_company,
            connected_by: current_user,
            project: target_project,
            installation_id: installation_id
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
          redirect_to github_setup_redirect_path(target_project)
        end

        def index
          integrations = current_company.integrations.company_wide.ransack(params[:q]).result
          respond_with integrations, each_serializer: IntegrationSerializer
        end

        def show
          integration = current_company.integrations.find(params[:id])
          respond_with integration, serializer: IntegrationSerializer
        end

        def create
          provider = params[:provider].to_s

          if provider == "gitlab"
            create_gitlab_integration(project_id: nil)
          else
            create_github_integration(project_id: nil)
          end
        end

        def destroy
          integration = current_company.integrations.find(params[:id])
          integration.destroy
          respond_with integration
        end

        private

        def create_gitlab_integration(project_id:, project: nil)
          integration = Integration.find_or_build_gitlab_for_token(
            company: current_company,
            connected_by: current_user,
            project: project
          )
          integration.project_id = project_id
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

        def create_github_integration(project_id:, project: nil)
          integration = current_company.integrations.new(
            provider: :github,
            connected_by: current_user,
            status: :inactive,
            project_id: project_id
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

        def github_setup_redirect_path(project)
          project ? "/company/projects/#{project.id}/integrations" : "/company/integrations"
        end

        # GitHub App passes `state` through the installation flow (e.g. state=project:123).
        def resolve_github_setup_project(state)
          return nil if state.blank?

          match = state.to_s.match(/\Aproject:(\d+)\z/)
          return nil unless match

          current_company.projects.find_by(id: match[1].to_i)
        end
      end
    end
  end
end
