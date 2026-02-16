# frozen_string_literal: true

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
              :session_config,
              :started_at,
              :finished_at,
              :collected_at,
              :created_at,
              :updated_at,
              # Usage (denormalized from UsageStatistic)
              :total_tokens,
              :input_tokens,
              :output_tokens,
              :cache_read_tokens,
              :cache_write_tokens,
              :cost_cents,
              :models,
              # Relationships
              :user_name,
              :user_email,
              :project_name

  def websocket_url
    return nil unless object.route_token.present?

    "#{Settings.traefik.ws_base}/t/#{object.route_token}/tty/ws"
  end

  def watcher_url
    return nil unless object.route_token.present?

    "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
  end

  def user_name
    object.user&.name
  end

  def user_email
    object.user&.email
  end

  def project_name
    object.project&.name
  end
end
