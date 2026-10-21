# frozen_string_literal: true

module Api
  module V1
    module Projects
      # The chat channels connected to the project's company, which its chat
      # triggers can listen to and its workflows can post to.
      class ChatChannelsController < ApplicationController
        def index
          rows = Chat::ChannelAccess.channels(current_project, provider: params[:provider].presence)
                                    .includes(chat_channel_connections: :requested_by)
          render json: { channels: rows.map { |row| channel_json(row) } }
        end

        def destroy
          conversation = Chat::ChannelAccess.channels(current_project).find(params[:id])
          Chat::ChannelDisconnect.call(conversation, company: current_project.company)
          head :no_content
        end

        private

        def channel_json(row)
          connection = row.chat_channel_connections.find { |c| c.company_id == current_project.company_id }
          Chat::ChannelAccess.describe(row).merge(
            connected_at: connection&.created_at&.iso8601,
            requested_by: connection&.requested_by&.name,
            posted_by: connection&.posted_by_name || connection&.posted_by_external_id
          )
        end
      end
    end
  end
end
