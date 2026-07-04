# frozen_string_literal: true

module PersonalTools
  class ListAssets < Base
    tool do
      display_name "List Assets"
      description "List the assets accessible from a project."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::AssetsPolicy, project: project)
      rows = Asset.accessible_from_project(project).order(updated_at: :desc).limit(100).map do |a|
        { id: a.id, name: a.name, kind: a.try(:kind), updated_at: a.updated_at }
      end
      success(project_id: project.id, assets: rows)
    end
  end
end
