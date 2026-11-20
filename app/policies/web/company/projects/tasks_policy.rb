# frozen_string_literal: true

module Web
  module Company
    module Projects
      class TasksPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
      end
    end
  end
end
