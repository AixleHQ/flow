# frozen_string_literal: true

class StepRunResource < ApplicationResource
  attributes :id, :step_id, :state, :step_note, :error_message,
             :terminal_session_id, :started_at, :completed_at

  attribute :step_name do |sr|
    sr.step&.name
  end

  attribute :step_position do |sr|
    sr.step&.position
  end

  attribute :allow_non_interactive do |sr|
    sr.step&.allow_non_interactive || false
  end

  attribute :depends_on_step_ids do |sr|
    sr.step&.depends_on_step_ids || []
  end

  attribute :depends_on_names do |sr|
    map = params[:step_name_map] || {}
    (sr.step&.depends_on_step_ids || []).filter_map { |did| map[did] }
  end

  attribute :terminal_session_state do |sr|
    sr.terminal_session&.state
  end

  attribute :terminal_url do |sr|
    ts = sr.terminal_session
    next nil unless ts&.route_token.present? && ts.active?

    ws_base = params.dig(:traefik, :ws_base)
    "#{ws_base}/t/#{ts.route_token}/tty/ws"
      .sub("wss://", "https://").sub("ws://", "http://")
      .sub("/ws", "")
  end

  attribute :ide_url do |sr|
    ts = sr.terminal_session
    next nil unless ts&.route_token.present? && ts.active?
    next nil if ts.mode == "non_interactive"

    http_base = params.dig(:traefik, :http_base)
    vscode_params = { folder: "/workspace", skipWelcome: "true" }
    token = ts.metadata&.dig("vscode_token")
    vscode_params[:tkn] = token if token.present?
    vscode_url = "#{http_base}/t/#{ts.route_token}/ide/?#{vscode_params.to_query}"

    "#{http_base}/t/#{ts.route_token}/fs/preload?#{{ to: vscode_url }.to_query}"
  end

  attribute :sub_step_runs do |sr|
    sr.sub_step_runs
      .sort_by { |ssr| ssr.sub_step&.position || 0 }
      .map { |ssr| SubStepRunResource.new(ssr).to_h }
  end
end
