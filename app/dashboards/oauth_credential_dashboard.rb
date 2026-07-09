# frozen_string_literal: true

require "administrate/base_dashboard"

# Read-only admin view of OAuth credentials (one token set per owner identity per
# authorization server). SECURITY: encrypted_access_token / encrypted_refresh_token
# are deliberately NOT listed — tokens never render in admin. Only status, identity,
# expiry and the non-secret `metadata` (SAFE_METADATA_KEYS) are shown.
class OauthCredentialDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    oauth_client: Field::BelongsTo,
    owner: Field::Polymorphic,
    mcp_server: Field::BelongsTo,
    provider: Field::String.with_options(searchable: true),
    status: Field::Select.with_options(include_blank: false, collection: %w[pending active error revoked]),
    scopes: Field::String,
    token_type: Field::String,
    expires_at: Field::DateTime,
    last_refreshed_at: Field::DateTime,
    refresh_failure_count: Field::Number,
    refresh_error: Field::String.with_options(truncate: 120),
    metadata: Field::JSONB,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    owner
    provider
    status
    expires_at
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    oauth_client
    owner
    mcp_server
    provider
    status
    scopes
    token_type
    expires_at
    last_refreshed_at
    refresh_failure_count
    refresh_error
    metadata
    created_at
    updated_at
  ].freeze

  # Created via the OAuth flow — read-only in admin.
  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.with_status(:active) },
    pending: ->(resources) { resources.with_status(:pending) },
    error: ->(resources) { resources.with_status(:error) },
    revoked: ->(resources) { resources.with_status(:revoked) },
    expiring: ->(resources) { resources.where(expires_at: ..30.minutes.from_now) }
  }.freeze

  def display_resource(credential)
    "#{credential.provider} — #{credential.owner_type}##{credential.owner_id}"
  end
end
