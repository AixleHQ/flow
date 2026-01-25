# frozen_string_literal: true

module Api
  module V1
    class TerminalSessionSerializer < ApplicationSerializer
      attributes :id,
                 :session_type,
                 :agent_type,
                 :state,
                 :project_id,
                 :container_id,
                 :route_token,
                 :websocket_url,
                 :watcher_url,
                 :artifacts_path,
                 :error_message,
                 :metadata,
                 :started_at,
                 :finished_at,
                 :collected_at,
                 :created_at,
                 :updated_at

      # WebSocket URL built from route_token
      # Format: ws://domain/t/{route_token}/tty/ws
      def websocket_url
        return nil unless object.route_token.present?

        "#{Settings.traefik.ws_base}/t/#{object.route_token}/tty/ws"
      end

      # Watcher URL built from route_token
      # Format: http://domain/t/{route_token}/fs
      def watcher_url
        return nil unless object.route_token.present?

        "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
      end
    end
  end
end
