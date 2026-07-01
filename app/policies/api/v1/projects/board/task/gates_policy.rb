# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        module Task
          class GatesPolicy < Api::V1::ApplicationPolicy
            def destroy? = project_writable?
          end
        end
      end
    end
  end
end
