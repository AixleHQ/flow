# frozen_string_literal: true

module Api
  module V1
    module Company
      class ProjectsController < ApplicationController
        def index
          projects = Project.for_user(current_user)
                            .includes(:project_collaborators)
                            .select(
                              "projects.*",
                              "(SELECT MAX(terminal_sessions.started_at) FROM terminal_sessions WHERE terminal_sessions.project_id = projects.id) AS cached_last_activity_at"
                            )
                            .ransack(q_params).result
          respond_with paginate(projects)
        end

        def show
          respond_with current_company.projects.find(params[:id])
        end

        def create
          project = current_company.projects.create(project_params.merge(owner: current_user))
          respond_with project
        end

        def update
          project = current_company.projects.find(params[:id])
          project.update(project_params)
          respond_with project
        end

        private

        def project_params
          params.require(:project).permit(:name, :description)
        end
      end
    end
  end
end
