# frozen_string_literal: true

module Web
  module Company
    module Projects
      # The page lists; writes go through the workflow triggers API and its policy.
      class TriggersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
      end
    end
  end
end
