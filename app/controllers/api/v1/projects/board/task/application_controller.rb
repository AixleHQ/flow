# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class ApplicationController < Api::V1::Projects::Board::ApplicationController
            private

            def current_task
              @current_task ||= current_board.board_tasks.find(params[:task_id])
            end
          end
        end
      end
    end
  end
end
