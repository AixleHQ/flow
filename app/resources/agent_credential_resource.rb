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
    credential.default_model
  end

  # Connection status.
  #
  # `error` comes first and is new: the refresh sweep has been able to condemn a
  # credential since it existed, and this attribute read only the expiry — so a row the
  # platform had given up on still rendered "Connected" whenever its expiry was nil or in
  # the future, and the user had no way to learn they needed to sign in again.
  #
  # The rest is derived from token expiry. A nil expiry (an API-key credential, or an
  # agent whose token carries no exp) reads as "active" — expiry unknown, not past.
  typelize %w[active expiring expired error]
  attribute :connection_status do |credential|
    exp = credential.expires_at
    if credential.error? then "error"
    elsif exp.nil? then "active"
    elsif exp <= Time.current then "expired"
    elsif exp <= 30.minutes.from_now then "expiring"
    else "active"
    end
  end

  # Why the platform gave up, in the vendor's own words (truncated to 500 chars when it
  # was recorded). Shown next to an `error` badge — "reconnect" without a reason is what
  # sends a user to support.
  typelize "string | null"
  attribute :refresh_error do |credential|
    credential.error? ? credential.refresh_error : nil
  end

  # Whether re-authenticating is the only remedy, so the UI can say so rather than imply
  # that waiting might help. True when this runtime cannot renew server-side
  # (BaseAdapter#credential_lifecycle) — Grok stores no refresh token at all — or when the
  # platform has already exhausted its retries.
  typelize :boolean
  attribute :reauth_required do |credential|
    credential.error? || credential.adapter.credential_lifecycle[:refresh] != :server
  rescue StandardError
    credential.error?
  end
end
