# frozen_string_literal: true

module Web
  module Company
    module Projects
      class IntegrationsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = manage_integrations?
        def update? = manage_integrations?
        def destroy? = manage_integrations?
        def slack_oauth_start? = manage_integrations?
        def github_app_install? = manage_integrations?

        private

        def manage_integrations?
          project_writable? && (admin? || project_owner?)
        end

        def project_owner?
          project&.owner_id == current_user.id
        end
      end
    end
  end
end
