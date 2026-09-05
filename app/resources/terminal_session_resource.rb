# frozen_string_literal: true

class TerminalSessionResource < ApplicationResource
  typelize_from TerminalSession

  attributes :id, :session_type, :agent_type, :state, :mode,
             :started_at, :finishing_at, :finished_at, :created_at,
             :total_tokens, :input_tokens, :output_tokens,
             :cache_read_tokens, :cache_write_tokens,
             :cost_cents, :models, :requested_model,
             :artifacts_reviewed,
             :error_message, :container_id,
             :project_id, :route_token, :configured_agent_id,
             :collected_at, :updated_at

  typelize "string | null"
  attribute :queued_at do |session|
    session.queued_at
  end

  typelize "string | null"
  attribute :wait_reason do |session|
    session.session_admission&.wait_reason
  end

  # Whether the REQUESTING user may open this session — see
  # TerminalSession#visible_to?. Screens that can list other people's sessions
  # pass `params: { viewer: current_user }`; without the param the payload is
  # unredacted, which is what the owner-scoped surfaces (API, Aixle Builder,
  # profile usage) want.
  #
  # What this redacts is CONTENT — the prompt and the metadata blobs, which say
  # what the person was working on. The route token and the URLs built from it
  # are deliberately NOT redacted: the container routes are gated at the proxy
  # (Api::V1::Internal::WsAuth, which re-reads the owner's preference on every
  # connection), and the log endpoint scopes its own lookup. Blanking them here
  # too would put the same rule in two places, with nothing to say which one is
  # authoritative when they drift.
  typelize :boolean
  attribute :viewable do |session|
    viewable_for?(session)
  end

  # Whether the REQUESTING user is the person whose session this is. Drives the
  # look-don't-touch presentation: a shared session renders the terminal behind
  # a click-blocking overlay, drops the editor, and hides the Finish button.
  #
  # A UI guardrail, not an access control — ttyd runs writable and the viewer
  # holds the route token, so opening it directly still gives a live shell.
  # Making that impossible needs a second, non-writable ttyd (or a restriction
  # at the proxy), not a frontend change.
  typelize :boolean
  attribute :owned_by_viewer do |session|
    viewer = params[:viewer]
    params.key?(:viewer) ? (viewer.present? && session.user_id == viewer.id) : true
  end

  typelize "string | null"
  attribute :initial_prompt do |session|
    viewable_for?(session) ? session.initial_prompt : nil
  end

  # Free-form jsonb columns — column inference only sees `unknown`. Expose as explicit attributes so
  # the keyless typelize applies (matches IntegrationResource#settings).
  typelize "Record<string, unknown> | null"
  attribute :context_metadata do |session|
    viewable_for?(session) ? session.context_metadata : nil
  end

  typelize "Record<string, unknown> | null"
  attribute :metadata do |session|
    viewable_for?(session) ? session.metadata : nil
  end

  typelize :string?
  attribute :websocket_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present?

    "#{Settings.traefik.ws_base}/t/#{session.route_token}/tty/ws"
  end

  # Endpoint that streams the captured terminal log so a finished session can be
  # replayed in the browser. Gated on terminal state only (a column read, so no
  # per-session query / N+1 when lists are serialized); the endpoint returns 404
  # for the rare finished session that captured no log, which the frontend treats
  # as an empty state.
  typelize :string?
  attribute :terminal_log_url do |session|
    next nil unless session.state.in?(%w[finished failed])

    "/api/v1/terminal_sessions/#{session.id}/terminal_log"
  end

  typelize :string?
  attribute :watcher_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present?
    next nil unless session.session_type == "auth_setup"

    "#{Settings.traefik.http_base}/t/#{session.route_token}/fs"
  end

  # True once the in-container credential helper reported that this user has no cloud
  # connection — which only happens because Claude Code's own Bedrock wizard asked it for
  # credentials. The auth modal reads this to show the connect step instead of waiting for
  # a token that will never appear: Bedrock writes no auth file, so `authenticated` stays
  # false forever on this path.
  typelize :boolean
  attribute :cloud_connect_requested do |session|
    next false unless session.session_type == "auth_setup"

    session.metadata&.dig("cloud_connect_requested_at").present?
  end

  typelize :string?
  attribute :ide_url do |session|
    next nil if session.queued? || session.cancelled?
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

  typelize "{ config_files?: Record<string, unknown>; bmad_enabled?: boolean; bmad_modules?: string[] }"
  attribute :session_config do |session|
    {
      "config_files" => session.config_files,
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

  # Ids only — a config item's VALUE never crosses into a serialized payload.
  attribute :config_item_ids do |session|
    session.config_items.map(&:id)
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

  private

  # No `viewer` param at all means "not a shared surface" — the caller already
  # scoped the query to the acting user (or to a screen that has no other
  # viewer), so nothing is redacted. Memoized per session id because every
  # redacted attribute asks again, once per row.
  def viewable_for?(session)
    return true unless params.key?(:viewer)

    @viewable ||= {}
    key = session.id
    return @viewable[key] if @viewable.key?(key)

    @viewable[key] = session.visible_to?(params[:viewer])
  end
end
