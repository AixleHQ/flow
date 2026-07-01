# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        module Task
          class WaitsPolicy < Web::Company::ApplicationPolicy
            def destroy? = project_writable?
          end
        end
      end
    end
  end
end
