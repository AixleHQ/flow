# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class WaitsController < Api::V1::Company::Projects::ApplicationController
              def destroy
                wait = current_task.task_waits.pending.find(params[:id])
                TaskService.remove_wait(wait: wait, actor: current_user)
                head :no_content
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end
            end
          end
        end
      end
    end
  end
end
