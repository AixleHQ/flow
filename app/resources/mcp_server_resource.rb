# frozen_string_literal: true

class MCPServerResource < ApplicationResource
  preserve_keys :env, :headers

  typelize headers: "Record<string, unknown>", env: "Record<string, unknown>", integration_id: :number?
  attributes :id, :name, :display_name, :url, :transport,
             :description, :kind, :scope_type, :scope_id, :enabled,
             :command, :integration_id, :created_at, :updated_at

  # SECURITY (oauth-unification §7): header/env VALUES can carry secrets (bearer
  # tokens, API keys, resolved config-item references) and must never round-trip to
  # the browser in cleartext. Mask the values but keep the KEYS so the UI can still
  # show which headers/env vars exist. The modal treats a masked "••••••" value as
  # "unchanged" and the write path drops it, so an edit never overwrites the stored
  # secret. preserve_keys keeps the masked hash serialized as a JSON object.
  attribute :headers do |server|
    (server.headers || {}).transform_values { "••••••" }
  end

  attribute :env do |server|
    (server.env || {}).transform_values { "••••••" }
  end

  typelize :boolean
  attribute :internal do |server|
    server.internal?
  end

  typelize :boolean
  attribute :managed do |server|
    server.managed?
  end

  typelize %w[internal company project]
  attribute :scope_indicator do |server|
    server.scope_indicator
  end

  # --- OAuth (oauth-unification §4.4 / §5) ---
  typelize %w[none static oauth]
  attribute :auth_type do |server|
    server.auth_type.to_s
  end

  typelize %w[shared per_user]
  attribute :credential_scope do |server|
    server.credential_scope.to_s
  end

  # Connection status for the CURRENT viewer: nil (non-oauth) | "pending" (no
  # credential yet) | "active" | "expiring" (near expiry) | "error". For per_user
  # servers the identity is the viewer (passed as params[:user]); for shared servers
  # it is the server's scope owner. When no user is supplied a per_user server reads
  # as "pending" (the viewer must connect).
  typelize :string?
  attribute :oauth_status do |server|
    next nil unless server.auth_type_oauth?

    owner = server.credential_scope_per_user? ? params[:user] : server.scope
    cred = owner && OauthCredential.for_mcp_server(server).for_owner(owner)
                                   .where.not(status: :revoked).order(updated_at: :desc).first
    next "pending" if cred.nil?
    next "error" if cred.error?

    cred.expired?(30.minutes) ? "expiring" : "active"
  end
end
