# frozen_string_literal: true

module Api
  module V1
    module Company
      class OverviewController < ApplicationController
        def show
          render json: CompanyOverviewService.new(current_company).call.to_h
        end
      end
    end
  end
end
