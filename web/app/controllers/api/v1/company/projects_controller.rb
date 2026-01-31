# frozen_string_literal: true

module Api
  module V1
    module Company
      class ProjectsController < ApplicationController
        def index
          projects = Project.for_user(current_user).ransack(q_params).result
          respond_with paginate(projects)
        end

        def create
          project = current_company.projects.create(project_params.merge(owner: current_user))
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
