# frozen_string_literal: true

module Api
  module V1
    module Projects
      # Every versioned entity (workflow, agent, skill, custom tool, MCP server) is
      # project-scoped with the same rule: anyone who can open the project reads its
      # history; anyone who can write to it reverts and restores.
      class EntityVersionsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def show? = project_accessible?
        def revert? = project_writable?
        def restore? = project_writable?
      end
    end
  end
end
