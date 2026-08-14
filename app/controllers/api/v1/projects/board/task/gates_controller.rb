# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class GatesController < Task::ApplicationController
            def destroy
              # Stale gates are deletable too: they are the ones an operator is most
              # likely to be clearing by hand after reconciliation gave up on them.
              gate = current_task.gates.unresolved.find(params[:id])
              TaskService.remove_gate(gate: gate, actor: current_user)
              head :no_content
            end
          end
        end
      end
    end
  end
end
