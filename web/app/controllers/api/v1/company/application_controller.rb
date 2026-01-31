# frozen_string_literal: true

module Api
  module V1
    module Company
      class ApplicationController < Api::V1::ApplicationController
        before_action :dynamic_authorize!

        def current_company
          @current_company ||= current_user.company
        end
      end
    end
  end
end
