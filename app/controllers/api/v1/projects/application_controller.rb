# frozen_string_literal: true

module Api
  module V1
    module Projects
      class ApplicationController < Api::V1::ApplicationController
        def current_project
          @current_project ||= Project.for_user(current_user).find(params[:project_id])
        end

        def policy_context
          ProjectContext.new(current_user, params, project: current_project)
        end
      end
    end
  end
end
