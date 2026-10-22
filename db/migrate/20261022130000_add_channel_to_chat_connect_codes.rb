# frozen_string_literal: true

# A code names the channel it is for, so posted anywhere else it connects
# nothing (docs/design/shared-chat-workspaces.md, decision 21).
class AddChannelToChatConnectCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_connect_codes, :channel_name, :string
    add_column :chat_connect_codes, :team_name, :string
  end
end
