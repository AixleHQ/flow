# frozen_string_literal: true

module Web
  module Company
    module Projects
      # The roles of a project's AWS OIDC integration: the same people who may connect it.
      class AwsOidcRolesPolicy < Web::Company::Projects::AwsOidcPolicy
        def create? = manage?
        def update? = manage?
        def destroy? = manage?
        def verify? = manage?
      end
    end
  end
end
