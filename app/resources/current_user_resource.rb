# frozen_string_literal: true

class CurrentUserResource < ApplicationResource
  attributes :id, :email, :name, :role, :state, :position, :preferred_agent_language,
             :selected_agents, :onboarding_state, :onboarding_completed_at,
             :default_agent_credential_id, :created_at, :updated_at

  one :company, resource: CompanyResource
  many :agent_credentials, resource: AgentCredentialResource

  attribute :configured_agents do |user|
    user.agent_credentials.pluck(:agent_type)
  end

  attribute :default_agent_runtime do |user|
    user.default_agent_runtime
  end
end
