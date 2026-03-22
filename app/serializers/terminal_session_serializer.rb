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
              :ide_url,
              :artifacts_path,
              :error_message,
              :metadata,
              :session_config,
              :started_at,
              :finished_at,
              :collected_at,
              :created_at,
              :updated_at,
              # Normalized config (from join tables + columns)
              :tool_ids,
              :skill_ids,
              :mcp_server_ids,
              :input_asset_ids,
              :repository_ids,
              :configured_agent_id,
              :mode,
              :initial_prompt,
              # Usage (denormalized from UsageStatistic)
              :total_tokens,
              :input_tokens,
              :output_tokens,
              :cache_read_tokens,
              :cache_write_tokens,
              :cost_cents,
              :models,
              # Context traceability
              :context_metadata,
              # Artifact review
              :artifacts_reviewed,
              :pending_artifacts_count,
              :session_logs_count,
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
    return nil unless object.session_type == "auth_setup"

    "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
  end

  def ide_url
    return nil unless object.route_token.present?
    return nil if object.mode == "non_interactive"

    base_url = "#{Settings.traefik.http_base}/t/#{object.route_token}/ide/"
    params = { folder: "/workspace" }
    token = object.metadata&.dig("vscode_token")
    params[:tkn] = token if token.present?
    "#{base_url}?#{params.to_query}"
  end

  def session_config
    {
      "config_files" => object.config_files,
      "env_vars" => object.env_vars
    }.compact_blank
  end

  def tool_ids
    object.tools.map(&:id)
  end

  def skill_ids
    object.skills.map(&:id)
  end

  def mcp_server_ids
    object.mcp_servers.map(&:id)
  end

  def input_asset_ids
    object.input_assets.map(&:id)
  end

  def repository_ids
    object.repositories.map(&:id)
  end

  def pending_artifacts_count
    object.output_assets.count { |a| a.status == "pending_review" }
  end

  def session_logs_count
    object.session_logs.size
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
