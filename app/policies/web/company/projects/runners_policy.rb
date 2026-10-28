# frozen_string_literal: true

module Web
  module Company
    module Projects
      # The project's runners page (docs/design/agent-runtimes/DESIGN.md §3.2).
      # It lists the project's own runners and the company's, but only the
      # project's own are managed here: a company runner is managed from company
      # settings, by a company admin.
      #
      # Stricter than integrations, where any writer connects one: a runner
      # receives the launching user's agent credential, so only someone with
      # authority over the project's trust boundary may point it somewhere.
      class RunnersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = index?

        def create? = manage?
        def update? = manage?
        def destroy? = manage?
        def disable? = manage?
        def enable? = manage?
        def revoke? = manage?

        private

        # The record is the runner when the controller has one, and the
        # `:runners` symbol when Pundit authorizes the action before the lookup.
        def manage?
          return false unless project_accessible? && (admin? || project.owner_id == current_user.id)

          !record.is_a?(Runner) || record.project_id == project.id
        end
      end
    end
  end
end
