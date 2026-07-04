# frozen_string_literal: true

module PersonalTools
  class UpdateAgent < Base
    tool do
      display_name "Update Agent"
      description "Update a project agent's fields."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :agent_id, type: :integer, description: "Agent id.", required: true
      param :name, type: :string, description: "Agent name."
      param :title, type: :string, description: "Title."
      param :persona, type: :string, description: "Persona."
      param :communication_style, type: :string, description: "Communication style."
      param :principles, type: :string, description: "Principles."
      param :icon, type: :string, description: "Icon key."
    end

    ATTRS = %w[name title persona communication_style principles icon].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::AgentsPolicy, project: project)
      agent = project.agents.find_by(id: params[:agent_id])
      return error("Agent not found in this project") unless agent

      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      agent.update!(attrs)
      success(id: agent.id, name: agent.name, updated_fields: attrs.keys)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update agent: #{e.message}")
    end
  end
end
