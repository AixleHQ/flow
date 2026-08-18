# frozen_string_literal: true

class StepRunResource < ApplicationResource
  attributes :id, :step_id, :state, :step_note, :error_message, :error_category,
             :terminal_session_id, :started_at, :completed_at

  typelize :string?
  attribute :step_name do |sr|
    sr.step&.name
  end

  typelize :number?
  attribute :step_position do |sr|
    sr.step&.position
  end

  typelize :boolean
  attribute :allow_non_interactive do |sr|
    sr.step&.allow_non_interactive || false
  end

  typelize "number[]"
  attribute :depends_on_step_ids do |sr|
    sr.step&.depends_on_step_ids || []
  end

  typelize "string[]"
  attribute :depends_on_names do |sr|
    map = params[:step_name_map] || {}
    (sr.step&.depends_on_step_ids || []).filter_map { |did| map[did] }
  end

  typelize :string?
  attribute :terminal_session_state do |sr|
    sr.terminal_session&.state
  end

  # The session card inside a run reports the same four numbers the list row
  # does, so a run reads as the sum of its sessions rather than as a black box.
  typelize :string?
  attribute :agent_type do |sr|
    sr.terminal_session&.agent_type
  end

  typelize :number
  attribute :total_tokens do |sr|
    sr.terminal_session&.total_tokens.to_i
  end

  typelize :number
  attribute :cost_cents do |sr|
    sr.terminal_session&.cost_cents.to_i
  end

  typelize :string?
  attribute :initial_prompt do |sr|
    sr.terminal_session&.initial_prompt
  end

  typelize :string?
  attribute :terminal_url do |sr|
    ts = sr.terminal_session
    # Gated on `ready?`, not the looser `active?` — the container only registers
    # its traefik route inside `exec`, which is what flips the session to
    # "ready". Handing out the URL any earlier (e.g. "not_started"/"running")
    # points the iframe at a route that doesn't exist yet and it 404s.
    next nil unless ts&.route_token.present? && ts.ready?

    ws_base = params.dig(:traefik, :ws_base)
    "#{ws_base}/t/#{ts.route_token}/tty/ws"
      .sub("wss://", "https://").sub("ws://", "http://")
      .sub("/ws", "")
  end

  typelize :string?
  attribute :ide_url do |sr|
    ts = sr.terminal_session
    next nil unless ts&.route_token.present? && ts.ready?
    next nil if ts.mode == "non_interactive"

    http_base = params.dig(:traefik, :http_base)
    vscode_params = { folder: "/workspace", skipWelcome: "true" }
    token = ts.metadata&.dig("vscode_token")
    vscode_params[:tkn] = token if token.present?
    vscode_url = "#{http_base}/t/#{ts.route_token}/ide/?#{vscode_params.to_query}"

    "#{http_base}/t/#{ts.route_token}/fs/preload?#{{ to: vscode_url }.to_query}"
  end

  typelize "SubStepRun[]"
  attribute :sub_step_runs do |sr|
    sr.sub_step_runs
      .sort_by { |ssr| ssr.sub_step&.position || 0 }
      .map { |ssr| SubStepRunResource.new(ssr).to_h }
  end
end
