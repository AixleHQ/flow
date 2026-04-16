# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class ApplicationController < Api::V1::Projects::ApplicationController
          private

          def current_board
            @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
