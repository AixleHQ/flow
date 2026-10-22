# frozen_string_literal: true

module Api
  module V1
    module Projects
      # A one-time code that connects the channel it is posted in to the
      # project's company (docs/design/shared-chat-workspaces.md §8). The code is
      # in the create response only; show reports whether it has been used.
      class ChatConnectCodesController < ApplicationController
        def create
          trigger = TriggerBinding.where(project: current_project).find(params[:trigger_id]) if params[:trigger_id].present?
          _record, payload = Chat::ConnectCodes.issue!(project: current_project, provider: params[:provider],
                                                       channel: params[:channel], user: current_user, trigger_binding: trigger)
          render json: payload, status: :created
        rescue Chat::ConnectCodes::Refused => e
          render json: { errors: [ e.message ] }, status: :unprocessable_entity
        end

        def show
          record = ChatConnectCode.where(project: current_project).find(params[:id])
          render json: Chat::ConnectCodes.describe(record, project: current_project)
        end
      end
    end
  end
end
