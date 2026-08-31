# frozen_string_literal: true

require "administrate/base_dashboard"

class AgentCredentialDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    user: Field::BelongsTo.with_options(searchable: true, searchable_fields: %w[email name]),
    agent_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[claude_code cursor_cli codex gemini_cli antigravity_cli grok]
    ),
    metadata: Field::String.with_options(truncate: 100),
    expires_at: Field::DateTime,
    last_used_at: Field::DateTime,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    # Virtual field for config data preview (read-only)
    config_keys: Field::String.with_options(truncate: 200)
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    user
    agent_type
    last_used_at
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    user
    agent_type
    config_keys
    metadata
    expires_at
    last_used_at
    created_at
    updated_at
  ].freeze

  # No form - credentials are created via auth flow, not admin
  FORM_ATTRIBUTES = %i[
    user
    agent_type
    expires_at
  ].freeze

  COLLECTION_FILTERS = {
    claude_code: ->(resources) { resources.for_agent("claude_code") },
    cursor_cli: ->(resources) { resources.for_agent("cursor_cli") },
    codex: ->(resources) { resources.for_agent("codex") },
    gemini_cli: ->(resources) { resources.for_agent("gemini_cli") },
    antigravity_cli: ->(resources) { resources.for_agent("antigravity_cli") },
    grok: ->(resources) { resources.for_agent("grok") },
    active: ->(resources) { resources.active },
    expired: ->(resources) { resources.where("expires_at < ?", Time.current) }
  }.freeze

  def display_resource(credential)
    "#{credential.user&.email} - #{credential.agent_type}"
  end
end
