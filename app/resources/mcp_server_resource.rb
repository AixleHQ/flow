# frozen_string_literal: true

class MCPServerResource < ApplicationResource
  preserve_keys :env, :headers

  typelize headers: "Record<string, unknown>", env: "Record<string, unknown>"
  attributes :id, :name, :url, :transport,
             :description, :kind, :scope_type, :scope_id, :enabled,
             :created_at, :updated_at

  # The whole launch line, not the `command` column. Storage keeps the executable
  # and its argv apart (see MCPServer#split_command_line); the form has always
  # edited one line and still posts one, which the model re-splits on write.
  # Spelled out rather than `:string?`, which Typelizer renders as OPTIONAL — the
  # key is always sent, and it is null for a server with no launch line at all.
  typelize command: "string | null"
  attribute :command do |server|
    server.command_line.presence
  end

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

  typelize %w[internal project]
  attribute :scope_indicator do |server|
    server.scope_indicator
  end

  # --- Connector provenance and tool-baseline health ---
  # Null/false for hand-authored servers, which is the honest answer: nobody
  # promised anything about a server someone typed in themselves.

  typelize :string?
  attribute :connector_name do |server|
    server.connector_name
  end

  typelize :string?
  attribute :connector_version do |server|
    server.connector_version
  end

  # The catalog entry's CURRENT registry status, resolved from a preloaded map
  # (params[:connector_statuses]) so a list of servers costs one query, not one
  # per row. "deleted" means the registry pulled the entry — possible spam,
  # malware, or illegal content — and the install keeps running with a warning
  # rather than being cut off underneath the user (decision, 2026-08-01).
  typelize :string?
  attribute :connector_status do |server|
    next nil if server.connector_name.blank?

    (params[:connector_statuses] || {})[server.connector_name]
  end

  # False only when the registry itself published an unpinnable version, so the
  # package runner may resolve a different release at any session start.
  typelize :boolean
  attribute :connector_version_pinned do |server|
    server.connector_version_pinned?
  end

  # The version the catalog now carries, when it differs from the installed one.
  # Null when they match, when the catalog entry is gone, or when either version
  # is unknown — offering an update on a guess is worse than staying quiet.
  typelize :string?
  attribute :connector_update_version do |server|
    next nil if server.connector_name.blank?

    catalog_version = (params[:connector_versions] || {})[server.connector_name]
    next nil if catalog_version.blank? || server.connector_version.blank?

    catalog_version == server.connector_version ? nil : catalog_version
  end

  # Whether the tools this server declares were ever recorded. stdio servers
  # are never probed (that would mean executing their package here), so the UI
  # must present absence as "not checked", never as "verified".
  typelize :boolean
  attribute :tool_baseline do |server|
    server.tool_baseline?
  end

  # Tools whose declarations changed after the install was approved — the
  # rug-pull shape. Empty when nothing changed.
  typelize tool_drift: "{ added?: string[]; removed?: string[]; changed?: string[]; detected_at?: string } | null"
  attribute :tool_drift do |server|
    server.tool_drift.presence
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

  # An operator-registered OAuth client, for a server whose authorization server
  # refuses to let us register ourselves. The client id is an identifier, not a
  # secret, so it round-trips; the secret never leaves the server — the UI learns
  # only that one is stored, and resubmits the mask when it is left alone.
  # Spelled out rather than `:string?`: the key is always sent, and it is null for a
  # server with no manual client (`:string?` would render it OPTIONAL instead).
  typelize "string | null"
  attribute :oauth_client_id do |server|
    server.manual_oauth_client&.client_id
  end

  typelize :boolean
  attribute :oauth_client_secret_present do |server|
    server.manual_oauth_client&.confidential? || false
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
    next "pending" if owner.nil?

    # Read the (eager-loaded when listed) oauth_credentials association in memory to
    # avoid an N+1 across the servers list; filter to the acting owner by type+id so
    # we never trigger a per-record owner load.
    cred = server.oauth_credentials
                 .reject(&:revoked?)
                 .select { |c| c.owner_type == owner.class.polymorphic_name && c.owner_id == owner.id }
                 .max_by(&:updated_at)
    next "pending" if cred.nil?
    next "error" if cred.error?

    cred.expired?(30.minutes) ? "expiring" : "active"
  end
end
