class CurrentUserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :position, :preferred_agent_language, :onboarding_completed_at, :created_at, :updated_at
  belongs_to :company, serializer: CompanySerializer
  has_many :agent_credentials, serializer: AgentCredentialSerializer

  # List of agent types that have credentials (replaces configured_agents)
  attribute :configured_agents

  def configured_agents
    object.agent_credentials.pluck(:agent_type)
  end
end
