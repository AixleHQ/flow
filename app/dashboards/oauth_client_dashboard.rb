# frozen_string_literal: true

require "administrate/base_dashboard"

# Read-only admin view of OAuth clients (registry/static, DCR, CIMD).
# SECURITY: encrypted_client_secret is deliberately NOT listed — client secrets
# never render in admin. `metadata` holds only non-secret discovery docs (prm/asm)
# and the DCR registration with bearer-capable fields already scrubbed.
class OauthClientDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    source: Field::Select.with_options(include_blank: false, collection: %w[static dcr cimd]),
    issuer: Field::String.with_options(searchable: true),
    client_id: Field::String.with_options(searchable: true),
    authorization_endpoint: Field::String,
    token_endpoint: Field::String,
    registration_endpoint: Field::String,
    scopes: Field::String,
    metadata: Field::JSONB,
    oauth_credentials: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    source
    issuer
    client_id
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    source
    issuer
    client_id
    authorization_endpoint
    token_endpoint
    registration_endpoint
    scopes
    metadata
    oauth_credentials
    created_at
    updated_at
  ].freeze

  # Machine-managed (Oauth::Providers registry / discovery / DCR) — read-only in admin.
  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    static: ->(resources) { resources.where(source: "static") },
    dcr: ->(resources) { resources.where(source: "dcr") },
    cimd: ->(resources) { resources.where(source: "cimd") }
  }.freeze

  def display_resource(client)
    "#{client.source}: #{client.issuer}"
  end
end
