# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SettingsPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def update? = project_writable?

        # Renaming a project is ordinary write access. Deciding how much of the
        # installation's session capacity it may occupy is not: the budget is
        # shared with every other project, including ones in companies this user
        # cannot see. Company admins only, and not while the company is on the
        # free trial, which runs one worker whatever its projects reserve.
        def manage_concurrency?
          company = context.company
          project_accessible? && admin? && !(company && Billing::Trial.workers_fixed?(company))
        end
      end
    end
  end
end
