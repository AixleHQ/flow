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
        # cannot see. Company admins only.
        def manage_concurrency? = project_accessible? && admin?
      end
    end
  end
end
