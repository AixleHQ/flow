# frozen_string_literal: true

module Web
  module Company
    class ProjectsPolicy < ApplicationPolicy
      def index?
        true
      end

      def show?
        current_project&.accessible_by?(current_user)
      end

      def create?
        true
      end

      def destroy?
        return false unless current_project

        current_project.admin?(current_user) || current_user.admin?
      end

      private

      def current_project
        return nil unless context.params[:id]

        @current_project ||= current_user.company.projects.find_by(id: context.params[:id])
      end
    end
  end
end
