# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Attaching a repository is the same authority as adding an agent, a tool
      # or an MCP server: it configures what a session runs with, inside a
      # project the actor can already write to. It used to require a company
      # admin, which left a project owner able to connect the GitHub
      # integration (IntegrationsPolicy) but not add a repository from it.
      class RepositoriesPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
