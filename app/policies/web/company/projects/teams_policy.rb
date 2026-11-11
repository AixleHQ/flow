# frozen_string_literal: true

module Web
  module Company
    module Projects
      class TeamsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        # The people who may change a trigger's Runs as: a team decides whose
        # subscription runs spend just as Runs as does.
        def create? = manage?
        def update? = manage?
        def destroy? = manage?
        # Anyone may take themselves out; the controller finds the membership.
        def leave? = project_accessible?

        def manage? = project_writable? && (admin? || project.owner_id == current_user.id)
      end
    end
  end
end
