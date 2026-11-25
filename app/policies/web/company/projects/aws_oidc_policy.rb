# frozen_string_literal: true

module Web
  module Company
    module Projects
      # AWS OIDC (docs/design/aws-oidc-integration.md §8). Connecting it decides which AWS
      # accounts may trust this project, so it is the project's owner's or a company admin's.
      class AwsOidcPolicy < Web::Company::ApplicationPolicy
        def connect? = manage?
        def disconnect? = manage?

        def manage?
          project_writable? && (admin? || project.admin?(current_user))
        end
      end
    end
  end
end
