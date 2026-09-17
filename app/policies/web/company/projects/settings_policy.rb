# frozen_string_literal: true

module Web
  module Company
    module Projects
      class SettingsPolicy < Web::Company::ApplicationPolicy
        def show? = project_accessible?
        def update? = project_writable?

        # Insights sharing is a security-sensitive project gate (same bar as
        # managing integrations): company admin or project owner only.
        def manage_insights_sharing?
          project_writable? && (admin? || project_owner?)
        end

        def regenerate_insights_connection_token? = manage_insights_sharing?

        private

        def project_owner?
          project&.owner_id == current_user.id
        end
      end
    end
  end
end
