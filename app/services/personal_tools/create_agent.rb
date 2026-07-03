# frozen_string_literal: true

module PersonalTools
  class CreateAgent < Base
    tool do
      display_name "Create Agent"
      description "Create a project agent (a reusable persona a workflow step can run as)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Agent name (identifier).", required: true
      param :title, type: :string, description: "Human-readable title.", required: true
      param :persona, type: :string, description: "Persona / role description.", required: true
      param :communication_style, type: :string, description: "How the agent communicates."
      param :principles, type: :string, description: "Operating principles."
      param :icon, type: :string, description: "Icon key."
    end

    ATTRS = %w[name title persona communication_style principles icon].freeze

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::AgentsPolicy, project: project)
      agent = project.agents.create!(params.slice(*ATTRS).compact)
      success(id: agent.id, name: agent.name, title: agent.title)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create agent: #{e.message}")
    end
  end
end
