# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Board
        module Task
          class ActivitiesPolicy < Web::Company::ApplicationPolicy
            def index? = project_accessible?
          end
        end
      end
    end
  end
end
