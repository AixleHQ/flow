# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Statistic
          class BoardTaskDistributionController < Projects::ApplicationController
            def show
              render json: BoardTaskDistributionService.new(current_company, project: current_project).call.to_h
            end
          end
        end
      end
    end
  end
end
