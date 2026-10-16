# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Connecting a project to a workspace the company bound is a connect like
      # any other on the integrations page.
      class BitbucketInstallationsPolicy < Web::Company::ApplicationPolicy
        def create? = project_writable?
      end
    end
  end
end
