# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SettingsPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def update? = project_writable?
      end
    end
  end
end
