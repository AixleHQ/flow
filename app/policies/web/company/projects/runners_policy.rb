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
      #
      # It authorizes the action only. Which runner a request may touch is the
      # controller's lookup: a write finds the project's own runners only.
      class RunnersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = index?

        def create? = manage?
        def update? = manage?
        def destroy? = manage?
        def disable? = manage?
        def enable? = manage?
        def revoke? = manage?
        # "Add machine": a registration token lets a machine join the runner.
        def registration_token? = manage?

        private

        def manage?
          project_accessible? && (admin? || project.owner_id == current_user.id)
        end
      end
    end
  end
end
