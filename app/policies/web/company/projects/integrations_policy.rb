# frozen_string_literal: true

module Web
  module Company
    module Projects
      class IntegrationsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        # Managing a project's integrations (incl. starting the Slack OAuth install)
        # is allowed for company admins AND the project's own owner.
        def create? = manage_integrations?
        def destroy? = manage_integrations?
        def slack_oauth_start? = manage_integrations?

        private

        def manage_integrations?
          project_accessible? && (current_user.admin? || project_owner?)
        end

        def project_owner?
          project&.owner_id == current_user.id
        end

        def project = context.project

        def project_accessible?
          project&.accessible_by?(current_user)
        end
      end
    end
  end
end
