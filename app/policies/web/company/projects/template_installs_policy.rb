# frozen_string_literal: true

module Web
  module Company
    module Projects
      # A template install's checklist page: anyone who can see the project.
      class TemplateInstallsPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
      end
    end
  end
end
