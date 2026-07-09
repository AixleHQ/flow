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

  # Connection status derived from token expiry. Agent credentials carry no error
  # state (a failed refresh is retried by the sweep; a dead token surfaces as
  # "expired" → the user re-authenticates). A nil expiry (e.g. an API-key credential,
  # or an agent whose token carries no exp) reads as "active" — expiry unknown, not past.
  typelize %w[active expiring expired]
  attribute :connection_status do |credential|
    exp = credential.expires_at
    if exp.nil? then "active"
    elsif exp <= Time.current then "expired"
    elsif exp <= 30.minutes.from_now then "expiring"
    else "active"
    end
  end
end
