# frozen_string_literal: true

module Api
  module V1
    module Company
      class ProjectsPolicy < ApplicationPolicy
        def index?
          true # All authenticated users can see their projects
        end

        def show?
          current_project&.accessible_by?(current_user)
        end

        def create?
          true # All authenticated users can create projects
        end

        def update?
          current_project&.accessible_by?(current_user)
        end

        private

        def current_project
          return nil unless context.params[:id]

          @current_project ||= current_user.company.projects.find_by(id: context.params[:id])
        end
      end
    end
  end
end
