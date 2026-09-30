# frozen_string_literal: true

module Web
  module Company
    module Projects
      # Adding a tracker from a connection the project can already see is the
      # same authority as adding a repository from one (the GitHub model,
      # docs/design/task-tracker-integrations.md §4.4). Connecting the
      # connection itself stays with IntegrationsPolicy.
      class TrackersPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def statuses? = project_accessible?
        def create? = project_writable?
        def update? = project_writable?
        def destroy? = project_writable?
      end
    end
  end
end
