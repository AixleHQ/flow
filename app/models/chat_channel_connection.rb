# frozen_string_literal: true

# A chat channel connected to a company. Only redeeming a connect code inside
# the channel creates one (Chat::ChannelConnect), so the channel's own members
# decided it (docs/design/shared-chat-workspaces.md §8).
class ChatChannelConnection < ApplicationRecord
  belongs_to :chat_conversation
  belongs_to :company
  belongs_to :requested_by, class_name: "User", optional: true

  validates :chat_conversation_id, uniqueness: { scope: :company_id }
  validate :conversation_connectable

  scope :for_company, ->(company) { where(company_id: company.is_a?(Company) ? company.id : company) }

  private

  def conversation_connectable
    errors.add(:chat_conversation, "is a direct chat") if chat_conversation&.direct?
  end
end
