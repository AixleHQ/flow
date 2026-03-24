# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class RepositoriesController < ApplicationController
          def index
            repositories = Repository.visible_for_project(current_project).includes(:integration)
            respond_with repositories, each_serializer: RepositorySerializer, project: current_project
          end

          def create
            integration = Integration.visible_for_project(current_project).find(params[:integration_id])
            repo_info = repository_service(integration).find_repo(params[:full_name])

            if repo_info.nil?
              render json: { error: "Repository not found or not accessible" }, status: :unprocessable_entity
              return
            end

            repository = current_project.repositories.create(
              integration: integration,
              full_name: repo_info[:full_name],
              source_branch: params[:source_branch].presence || repo_info[:default_branch],
              clone_url: repo_info[:clone_url],
              is_private: repo_info[:is_private],
              description: repo_info[:description],
              purpose: params[:purpose]
            )

            if integration.gitlab?
              Gitlab::RepositoryService.new(integration).configure_webhook(repository)
            end

            respond_with repository, serializer: RepositorySerializer
          end

          def update
            repository = current_project.repositories.find(params[:id])
            repository.update(repository_params)
            respond_with repository, serializer: RepositorySerializer
          end

          def destroy
            repository = current_project.repositories.find(params[:id])
            repository.destroy
            respond_with repository
          end

          def available
            integration = Integration.visible_for_project(current_project).find(params[:integration_id])
            repos = repository_service(integration).list_available
            render json: { items: repos }
          end

          def branches
            integration = Integration.visible_for_project(current_project).find(params[:integration_id])
            branches = repository_service(integration).list_branches(params[:full_name])
            render json: { items: branches }
          end

          def webhook_info
            repository = Repository.visible_for_project(current_project).find(params[:id])

            unless repository.integration.gitlab?
              render json: { error: "webhook_info is only available for GitLab repositories" }, status: :unprocessable_entity
              return
            end

            render json: {
              url: "#{Settings.protocol}://#{Settings.domain}/webhooks/gitlab",
              secret_token: repository.webhook_secret,
              trigger: "Pipeline events"
            }
          end

          private

          def repository_service(integration)
            case integration.provider.to_sym
            when :github then Github::RepositoryService.new(integration)
            when :gitlab then Gitlab::RepositoryService.new(integration)
            else raise "Unsupported provider: #{integration.provider}"
            end
          end

          def repository_params
            params.require(:repository).permit(:source_branch, :purpose)
          end
        end
      end
    end
  end
end
