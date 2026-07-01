# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        module Task
          class StatisticsPolicy < Web::Company::ApplicationPolicy
            def show? = project_accessible?
          end
        end
      end
    end
  end
end
