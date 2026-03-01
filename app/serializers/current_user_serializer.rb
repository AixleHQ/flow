class CurrentUserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :position, :preferred_agent_language,
             :selected_agents, :onboarding_state, :onboarding_completed_at,
             :default_agent_credential_id, :created_at, :updated_at
  belongs_to :company, serializer: CompanySerializer
  has_many :agent_credentials, serializer: AgentCredentialSerializer

  attribute :configured_agents
  attribute :default_agent_runtime

  def configured_agents
    object.agent_credentials.pluck(:agent_type)
  end

  def default_agent_runtime
    object.default_agent_runtime
  end
end
