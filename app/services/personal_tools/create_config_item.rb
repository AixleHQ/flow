# frozen_string_literal: true

module PersonalTools
  class CreateConfigItem < Base
    tool do
      display_name "Create Config Item"
      description "Create a project config item. item_type 'secret' stores the value encrypted; 'variable' is plain."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Item name (identifier).", required: true
      param :value, type: :string, description: "Value.", required: true
      param :item_type, type: :string, description: "secret or variable (default variable).", enum: %w[secret variable]
      param :description, type: :string, description: "What this config is for."
    end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::ConfigItemsPolicy, project: project)
      item = ConfigItem.create!(scope: project, name: params[:name], value: params[:value],
                                item_type: params[:item_type].presence || "variable", description: params[:description])
      success(id: item.id, name: item.name, item_type: item.item_type)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create config item: #{e.message}")
    end
  end
end
