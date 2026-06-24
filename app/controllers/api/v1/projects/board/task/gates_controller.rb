# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class GatesController < Task::ApplicationController
            def destroy
              wait = current_task.gates.pending.find(params[:id])
              TaskService.remove_gate(wait: wait, actor: current_user)
              head :no_content
            end
          end
        end
      end
    end
  end
end
