# frozen_string_literal: true

# One row per config-item value handed to an agent: through `get_config_item`, or
# inside an MCP server's header or env value written into the container.
#
# Attachment is gated on project access alone, so the project is the whole trust
# boundary — this table is the only thing that can answer "which session read
# STRIPE_KEY, and who was driving it". It is written at fetch time because
# nothing else we keep could reconstruct it later.
#
# The VALUE IS NEVER STORED HERE. The name and type are denormalized so a row
# still reads after the item is renamed or deleted; the associations are
# therefore optional and carry no dependent-destroy.
class ConfigItemAccess < ApplicationRecord
  belongs_to :config_item, optional: true
  belongs_to :terminal_session, optional: true
  belongs_to :user, optional: true

  CHANNEL_TOOL = "get_config_item"
  CHANNEL_MCP_CONFIG = "mcp_config"

  validates :config_item_name, presence: true
  validates :item_type, presence: true
  validates :channel, inclusion: { in: [ CHANNEL_TOOL, CHANNEL_MCP_CONFIG ] }

  # `created_at` only — an audit row is never updated, so the table carries no
  # `updated_at` column (Rails writes whichever timestamp columns exist).
  scope :recent_first, -> { order(created_at: :desc) }

  # Records the fetch. Takes the item rather than ids so the denormalized copy
  # can never disagree with the row it describes.
  def self.record!(config_item:, session:, user:, channel: CHANNEL_TOOL)
    create!(
      config_item: config_item,
      terminal_session: session,
      user: user,
      config_item_name: config_item.name,
      item_type: config_item.item_type.to_s,
      channel: channel
    )
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[config_item_id config_item_name item_type channel terminal_session_id user_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[config_item terminal_session user]
  end
end
