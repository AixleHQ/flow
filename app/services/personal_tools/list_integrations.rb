# frozen_string_literal: true

module PersonalTools
  class ListIntegrations < Base
    tool do
      display_name "List Integrations"
      description "List the integrations (GitHub, Slack, Coder, ...) visible to a project, with connection status."
      audience :user
      tags :integrations
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::IntegrationsPolicy, project: project)

      rows = Integration.visible_for_project(project).limit(100).map do |i|
        { id: i.id, provider: i.provider, name: i.name, status: i.status,
          scope: i.project_id ? "project" : "company" }
      end
      success(project_id: project.id, integrations: rows)
    end
  end
end
