# frozen_string_literal: true

module PersonalTools
  class UpdateConfigItem < Base
    tool do
      display_name "Update Config Item"
      description "Update a project config item's value or description."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :config_item_id, type: :integer, description: "Config item id.", required: true
      param :value, type: :string, description: "New value."
      param :description, type: :string, description: "New description."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::ConfigItemsPolicy, project: project)
      item = project.config_items.find_by(id: params[:config_item_id])
      return error("Config item not found in this project") unless item

      attrs = {}
      attrs[:value] = params[:value] if params.key?(:value)
      attrs[:description] = params[:description] if params.key?(:description)
      return error("No fields to update") if attrs.empty?

      item.update!(attrs)
      success(id: item.id, name: item.name, updated_fields: attrs.keys.map(&:to_s))
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update config item: #{e.message}")
    end
  end
end
