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
             :project_id, :user_id, :route_token, :configured_agent_id,
             :collected_at, :updated_at

  typelize "string | null"
  attribute :queued_at do |session|
    session.queued_at
  end

  typelize "string | null"
  attribute :wait_reason do |session|
    session.session_admission&.wait_reason
  end

  # Why the session is not up yet, as a fact rather than as the wait_reason
  # column's insert default — see SessionAdmission#launch_phase.
  typelize "string | null"
  attribute :launch_phase do |session|
    session.session_admission&.launch_phase
  end

  # Whatever went wrong on the way to the runtime: a preflight the launch relay
  # refused, a Temporal dispatch that failed, a capacity refusal. Without it
  # every one of those looked to the user like an ordinary queue wait.
  typelize "string | null"
  attribute :launch_error do |session|
    session.session_admission&.last_error.presence
  end

  # Whether the REQUESTING user may open this session — see
  # TerminalSession#visible_to?. Every caller passes `params: { viewer: current_user }`;
  # without it the payload is redacted as for a stranger and carries no container
  # ticket, so a forgotten param cannot hand out someone else's session.
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
  # look-don't-touch presentation: a shared session renders the read-only
  # terminal, drops the editor, and hides the Finish button. The proxy enforces
  # the same line (Api::V1::Internal::WsAuth refuses the writable terminal and
  # the IDE to anyone but the owner).
  typelize :boolean
  attribute :owned_by_viewer do |session|
    owned_by_viewer?(session)
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

  # A refused agent login, then its renewal (Sessions::AuthPause). An interactive session is
  # never typed into, so this is how its person learns the login is back.
  RENEWED_NOTICE_FOR = 30.minutes

  typelize "{ state: 'expired' | 'renewed'; agentType: string; at: string } | null"
  attribute :auth_notice do |session|
    next nil unless session.active?

    paused_at = session.metadata&.dig("auth_paused_at")
    renewed_at = session.metadata&.dig("auth_renewed_at")
    if paused_at.present?
      { state: "expired", agent_type: session.agent_type, at: paused_at }
    elsif renewed_at.present? && Time.zone.parse(renewed_at.to_s)&.after?(RENEWED_NOTICE_FOR.ago)
      { state: "renewed", agent_type: session.agent_type, at: renewed_at }
    end
  end

  # The IDE's connection token stays with the owner: the IDE is theirs alone.
  typelize "Record<string, unknown> | null"
  attribute :metadata do |session|
    next nil unless viewable_for?(session)

    owned_by_viewer?(session) ? session.metadata : session.metadata&.except("vscode_token")
  end

  typelize "string | null"
  attribute :websocket_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present?

    surface = owned_by_viewer?(session) ? "tty" : "view"
    with_ticket("#{Settings.traefik.ws_base}/t/#{session.route_token}/#{surface}/ws", session)
  end

  # Where the owner's terminal uploads a pasted image; nobody else may write
  # into the container.
  typelize "string | null"
  attribute :upload_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present? && owned_by_viewer?(session)

    with_ticket("#{Settings.traefik.http_base}/t/#{session.route_token}/upload", session)
  end

  # Endpoint that streams the captured terminal log so a finished session can be
  # replayed in the browser. Gated on terminal state only (a column read, so no
  # per-session query / N+1 when lists are serialized); the endpoint returns 404
  # for the rare finished session that captured no log, which the frontend treats
  # as an empty state.
  typelize "string | null"
  attribute :terminal_log_url do |session|
    next nil unless session.state.in?(%w[finished failed])

    "/api/v1/terminal_sessions/#{session.id}/terminal_log"
  end

  typelize "string | null"
  attribute :watcher_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present?
    next nil unless session.session_type == "auth_setup"

    with_ticket("#{Settings.traefik.http_base}/t/#{session.route_token}/fs", session)
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

  typelize "string | null"
  attribute :ide_url do |session|
    next nil if session.queued? || session.cancelled?
    next nil unless session.route_token.present?
    next nil if session.mode == "non_interactive"
    next nil unless owned_by_viewer?(session)

    vscode_params = { folder: "/workspace", skipWelcome: "true" }
    token = session.metadata&.dig("vscode_token")
    vscode_params[:tkn] = token if token.present?
    vscode_url = "#{Settings.traefik.http_base}/t/#{session.route_token}/ide/?#{vscode_params.to_query}"

    preload_base = "#{Settings.traefik.http_base}/t/#{session.route_token}/fs/preload"
    with_ticket("#{preload_base}?#{{ to: vscode_url }.to_query}", session)
  end

  typelize :string
  attribute :cable_stream do |session|
    InertiaCable::Streams::StreamName.signed_stream_name(session)
  end

  # File paths are data, not field names: as hash keys every camelizing pass (this
  # resource, then Inertia's prop transformer) would rewrite them —
  # "references/a.md" into "References::A.md" — so they travel as values.
  typelize "{ configFiles: Array<{ path: string; content: string }>; bmadEnabled?: boolean; bmadModules?: string[] }"
  attribute :session_config do |session|
    {
      "config_files" => session.config_files.map { |path, content| { "path" => path, "content" => content } },
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

  # Attached repositories that did not clone, and why. They are left out of
  # the agent's context, so without this a missing checkout has no explanation.
  typelize "Array<{ id: number; fullName: string; error: string }>"
  attribute :failed_repositories do |session|
    next [] unless viewable_for?(session)

    Array(session.metadata&.dig("failed_repos")).map { |f| f.to_h.slice("id", "full_name", "error") }
  end

  typelize "string | null"
  attribute :user_name do |session|
    session.user&.name
  end

  typelize "string | null"
  attribute :user_email do |session|
    session.user&.email
  end

  typelize "string | null"
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

  # Served from a host of their own, container URLs carry the viewer's pass
  # (ContainerTicket); on the app's host they are unchanged.
  def with_ticket(url, session)
    ContainerTicket.append(url, user: params[:viewer], session: session)
  end

  def owned_by_viewer?(session)
    viewer = params[:viewer]
    viewer.present? && session.user_id == viewer.id
  end

  # Memoized per session id because every redacted attribute asks again, once per row.
  def viewable_for?(session)
    return false if params[:viewer].nil?

    @viewable ||= {}
    key = session.id
    return @viewable[key] if @viewable.key?(key)

    @viewable[key] = session.visible_to?(params[:viewer])
  end
end
