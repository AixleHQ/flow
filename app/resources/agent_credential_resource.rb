# frozen_string_literal: true

class AgentCredentialResource < ApplicationResource
  attributes :id, :agent_type, :default_model, :last_used_at, :expires_at, :created_at, :updated_at

  typelize "string[]"
  attribute :config_keys do |credential|
    credential.config_data.keys
  rescue StandardError
    []
  end

  typelize :string?
  attribute :default_model do |credential|
    credential.metadata&.dig("default_model")
  end
end
