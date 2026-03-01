# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Workflows
          class StepsController < ApplicationController
            include StepsActions

            private

            def current_workflow
              @current_workflow ||= Workflow.visible_for_project(current_project).find(params[:workflow_id])
            end
          end
        end
      end
    end
  end
end
