# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class ApplicationController < Api::V1::Company::ApplicationController
          private

          def policy_context
            ProjectContext.new(current_user, params, project: current_project)
          end

          def current_project
            @current_project ||= current_company.projects.find(params[:project_id])
          end
        end
      end
    end
  end
end
