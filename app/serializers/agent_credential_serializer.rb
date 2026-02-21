# frozen_string_literal: true

class AgentCredentialSerializer < ApplicationSerializer
  attributes :id, :agent_type, :config_keys, :last_used_at, :expires_at, :created_at, :updated_at

  # Show which config keys are present (not the actual values)
  def config_keys
    object.config_data.keys
  rescue StandardError
    []
  end
end
