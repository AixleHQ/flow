# frozen_string_literal: true

module PersonalTools
  class DeleteConfigItem < Base
    tool do
      display_name "Delete Config Item"
      description "Delete a project config item."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :config_item_id, type: :integer, description: "Config item id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::ConfigItemsPolicy, project: project)
      item = project.config_items.find_by(id: params[:config_item_id])
      return error("Config item not found in this project") unless item

      name = item.name
      item.destroy
      success(deleted_config_item_id: params[:config_item_id].to_i, name: name)
    end
  end
end
