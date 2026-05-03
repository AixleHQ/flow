# frozen_string_literal: true

class TerminalSessionResource < ApplicationResource
  typelize_from TerminalSession

  attributes :id, :session_type, :agent_type, :state, :mode,
             :started_at, :finished_at, :created_at,
             :total_tokens, :input_tokens, :output_tokens,
             :cache_read_tokens, :cache_write_tokens,
             :cost_cents, :models, :requested_model,
             :artifacts_reviewed, :initial_prompt,
             :error_message, :container_id,
             :project_id, :route_token, :configured_agent_id,
             :context_metadata, :metadata, :collected_at, :updated_at

  typelize :string?
  attribute :websocket_url do |session|
    next nil unless session.route_token.present?

    "#{Settings.traefik.ws_base}/t/#{session.route_token}/tty/ws"
  end

  typelize :string?
  attribute :watcher_url do |session|
    next nil unless session.route_token.present?
    next nil unless session.session_type == "auth_setup"

    "#{Settings.traefik.http_base}/t/#{session.route_token}/fs"
  end

  typelize :string?
  attribute :ide_url do |session|
    next nil unless session.route_token.present?
    next nil if session.mode == "non_interactive"

    vscode_params = { folder: "/workspace", skipWelcome: "true" }
    token = session.metadata&.dig("vscode_token")
    vscode_params[:tkn] = token if token.present?
    vscode_url = "#{Settings.traefik.http_base}/t/#{session.route_token}/ide/?#{vscode_params.to_query}"

    preload_base = "#{Settings.traefik.http_base}/t/#{session.route_token}/fs/preload"
    "#{preload_base}?#{{ to: vscode_url }.to_query}"
  end

  typelize :string?
  attribute :cable_stream do |session|
    InertiaCable::Streams::StreamName.signed_stream_name(session)
  end

  attribute :session_config do |session|
    {
      "config_files" => session.config_files,
      "env_vars" => session.env_vars,
      "bmad_enabled" => session.bmad_enabled?,
      "bmad_modules" => session.bmad_enabled? ? session.bmad_modules : nil
    }.compact
  end

  attribute :tool_ids do |session|
    session.tools.map(&:id)
  end

  attribute :skill_ids do |session|
    session.skills.map(&:id)
  end

  attribute :mcp_server_ids do |session|
    session.mcp_servers.map(&:id)
  end

  attribute :input_asset_ids do |session|
    session.input_assets.map(&:id)
  end

  attribute :repository_ids do |session|
    session.repositories.map(&:id)
  end

  typelize :string?
  attribute :user_name do |session|
    session.user&.name
  end

  typelize :string?
  attribute :user_email do |session|
    session.user&.email
  end

  typelize :string?
  attribute :project_name do |session|
    session.project&.name
  end

  typelize :number
  attribute :pending_artifacts_count do |session|
    if session.respond_to?(:cached_pending_review_assets_count)
      session.cached_pending_review_assets_count.to_i
    else
      session.output_assets.count { |a| a.status == "pending_review" }
    end
  end

  typelize :number
  attribute :session_logs_count do |session|
    if session.respond_to?(:cached_session_logs_count)
      session.cached_session_logs_count.to_i
    else
      session.session_logs.size
    end
  end
end
