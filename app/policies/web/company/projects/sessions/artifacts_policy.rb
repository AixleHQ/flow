# frozen_string_literal: true

module Web
  module Company
    module Projects
      module Sessions
        class ArtifactsPolicy < Web::Company::ApplicationPolicy
          def index? = project_accessible?
          def review? = project_writable?
        end
      end
    end
  end
end
