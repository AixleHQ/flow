# frozen_string_literal: true

module Api
  module V1
    module Company
      class ProjectsPolicy < ApplicationPolicy
        def index?
          true # All authenticated users can see their projects
        end

        def create?
          true # All authenticated users can create projects
        end
      end
    end
  end
end
