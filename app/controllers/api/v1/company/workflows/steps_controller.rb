# frozen_string_literal: true

module Api
  module V1
    module Company
      module Workflows
        class StepsController < ApplicationController
          include StepsActions

          private

          def current_workflow
            @current_workflow ||= current_company.workflows.active.find(params[:workflow_id])
          end
        end
      end
    end
  end
end
