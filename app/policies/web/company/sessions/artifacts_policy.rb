# frozen_string_literal: true

module Web
  module Company
    module Sessions
      class ArtifactsPolicy < Web::Company::ApplicationPolicy
        def index? = true
        def review? = true
      end
    end
  end
end
