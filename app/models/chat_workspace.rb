# frozen_string_literal: true

# A Slack workspace or a Microsoft 365 tenant, which several companies may
# connect as peers (docs/design/shared-chat-workspaces.md §5–§7). It owns the
# channel registry; each company's Integration is its own link to it.
class ChatWorkspace < ApplicationRecord
  has_many :integrations, dependent: :nullify
  has_many :chat_conversations, dependent: :destroy

  validates :provider, inclusion: { in: Chat::PROVIDERS.keys }
  validates :external_id, presence: true, uniqueness: { scope: :provider }

  def self.for!(provider:, external_id:, name: nil)
    workspace = find_or_create_by!(provider: provider.to_s, external_id: external_id.to_s) { |row| row.name = name }
    workspace.update!(name: name) if name.present? && workspace.name != name
    workspace
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def active_integrations = integrations.active.where(provider: provider)

  # Any company's install answers what concerns the workspace as a whole
  # (connect, help, commands): they all speak as the same bot.
  def posting_integration = active_integrations.order(:id).first
end
