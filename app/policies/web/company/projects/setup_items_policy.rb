# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Acting on a checklist item writes to the project (a secret, a trigger).
      class SetupItemsPolicy < Web::Company::ApplicationPolicy
        def update? = project_writable?
      end
    end
  end
end
