# frozen_string_literal: true

module Web
  module Company
    module Projects
      class OwnershipsPolicy < Web::Company::ApplicationPolicy
        # The same people who may delete the project: its owner or a company admin.
        def update? = project_writable? && (admin? || project.owner_id == current_user.id)
      end
    end
  end
end
