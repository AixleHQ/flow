class CurrentUserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :position, :preferred_agent_language, :configured_agents, :onboarding_completed_at, :created_at, :updated_at
  belongs_to :company, serializer: CompanySerializer
end
