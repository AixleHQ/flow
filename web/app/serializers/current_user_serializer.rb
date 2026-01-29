class CurrentUserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :position, :preferred_agent_language,
             :selected_agents, :onboarding_state, :onboarding_completed_at, :created_at, :updated_at
  belongs_to :company, serializer: CompanySerializer
  has_many :agent_credentials, serializer: AgentCredentialSerializer

  # List of agent types that have credentials
  attribute :configured_agents

  def configured_agents
    object.agent_credentials.pluck(:agent_type)
  end
end
