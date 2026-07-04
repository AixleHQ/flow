# frozen_string_literal: true

module PersonalTools
  class ListConfigItems < Base
    tool do
      display_name "List Config Items"
      description "List a project's config items (env vars and secrets). Secret VALUES are never returned — only masked."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::ConfigItemsPolicy, project: project)
      rows = project.config_items.limit(100).map do |ci|
        { id: ci.id, name: ci.name, item_type: ci.item_type, value: ci.display_value, description: ci.description }
      end
      success(project_id: project.id, config_items: rows)
    end
  end
end
