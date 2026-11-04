# frozen_string_literal: true

# A code asked for from one install's channel list connects a channel in that
# install's workspace only, when a company has connected several workspaces of
# one messenger (docs/design/shared-chat-workspaces.md, decision 24).
class AddIntegrationToChatConnectCodes < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_connect_codes, :integration, foreign_key: { on_delete: :cascade }
  end
end
