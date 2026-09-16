# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "shellwords"
require "sqlite3"
require "tempfile"

module Agents
  # AWS Kiro CLI adapter (binary `kiro-cli`, installed from https://cli.kiro.dev/install).
  #
  # Config layout inside the container:
  #   ~/.local/share/kiro-cli/data.sqlite3 — the CLI's own state store, and the ONLY
  #                         place a login is kept. It is a SQLite database, not JSON.
  #   ~/.kiro/settings/mcp.json — MCP servers (shared with Kiro IDE; user scope).
  #   ~/.kiro/steering/*.md — always-loaded project/user standards. On the CLI the
  #                         `inclusion:` frontmatter modes are ignored and everything
  #                         in the directory is loaded, which is what makes this the
  #                         right home for the Aixle session context.
  #   ~/.kiro/skills/     — where `skills add -g -a kiro-cli` installs skills
  #                         (Kiro implements the open Agent Skills standard).
  #
  # Auth: the auth container runs the device-code login (AgentBaseStrategy::AUTH_COMMANDS).
  # Kiro's default login opens a browser, which cannot work here — the CLI says so
  # itself and points at `--use-device-flow`, which prints a URL and a one-time code
  # the user completes on their own device.
  #
  # Because the login lands in a SQLite database rather than a JSON document, two
  # things differ from every other runtime here:
  #
  #   * The watcher cannot decide completion by a key lookup, and cannot use the file's
  #     existence either: the database is created the moment the CLI first runs, and a
  #     device-registration row lands as soon as the code is displayed. What appears
  #     only on success is the token payload, so completion is a byte-marker test on
  #     the file (AUTH_MARKERS, and `__contains__:` in the watcher).
  #   * The credential is an opaque base64 blob of the database, written back byte for
  #     byte. It is read only to lift the bearer and profile ARN out (#auth_record) —
  #     never rewritten. Nothing is keyed on the token ROW's name: that name is derived
  #     from the login method the user picked, and an earlier version that gated on one
  #     discarded real logins, leaving a runtime that looked configured while every
  #     session started signed out.
  #
  # Billing note: Kiro meters in credits, not tokens, so a session's cost is credits
  # priced at the account's own overage rate, and token counts stay zero. Three sources,
  # best first, because each covers a case the next one down does not:
  #
  #   1. The CLI's OpenTelemetry export (#ingest_usage). Its endpoint is configurable,
  #      so the platform points it at the same collector Claude Code reports into, and
  #      `kiro_cli_credits_consumed` arrives per turn with the model attached. Exact and
  #      attributable to this session.
  #   2. The `usageSummary` activity the CLI posts to its own backend, captured in the
  #      MITM log (#collect_usage). Same figures, read at cleanup rather than streamed —
  #      the answer when telemetry was not reaching us.
  #   3. The movement of the ACCOUNT's credit counter across the session. Coarse: a
  #      concurrent session or the user's own Kiro IDE lands in the same number. Last
  #      resort, and the reason a baseline is seeded at login.
  class KiroCliAdapter < BaseAdapter
    # Where the CLI keeps its login. The stored blob is written straight here for a new
    # session: every process in an agent container runs as root, so a file the platform
    # writes is one the CLI can also open read-write — no staging copy, and therefore
    # no shell prefix on the launch command.
    STATE_PATH = ".local/share/kiro-cli/data.sqlite3"

    # Startup questions the CLI would otherwise ask, pre-answered. Keys and their
    # meanings are the CLI's own (`kiro-cli settings list --all`); the file is where it
    # records the answers itself, verified by watching it change after answering the
    # trust prompt by hand.
    #
    #   * the trust-all gate is a blocking confirmation on every `chat --trust-all-tools`
    #     startup. In an interactive terminal it is one keypress; in a non_interactive
    #     workflow step nobody can answer it and the session sits at `ready` forever —
    #     the failure Codex's trust dialog already caused once (task #605).
    #   * auto-update would pull a different CLI than the image pins, and the change is
    #     thrown away with the container anyway.
    #
    # `telemetry.enabled` is deliberately NOT set here, and neither is
    # `KIRO_DISABLE_TELEMETRY`. Both were, until measuring what they do: the CLI's
    # telemetry is its OpenTelemetry export, and turning it off takes
    # `kiro_cli_credits_consumed` with it — a container with the setting false sent
    # nothing but `kiro_cli_daily_heartbeat`, and the env var stopped the export
    # entirely. Silencing it is not a privacy win either, because what the export goes
    # to is configurable: #default_env_vars points it at the platform's own collector
    # (its default target is Kiro's `telemetry.desktop.kiro.dev`), so the traffic is
    # redirected rather than duplicated.
    CLI_SETTINGS = {
      "chat.disableTrustAllConfirmation" => true,
      "app.disableAutoupdates" => true
    }.freeze

    # Kiro's current engine. Still opt-in behind this flag as of CLI 2.21.3 (verified
    # against the shipping binary) — the changelog has carried "Available in V3 mode
    # (kiro-cli --v3)" since 2.8.
    V3_FLAG = "--v3"

    # V3 replaced the trust flags with a permissions policy whose default is to ask
    # before anything not explicitly allowed — which nobody can answer in a
    # non_interactive workflow step. `--trust-all-tools` still works as a session-scope
    # override ("continues to function for CI use cases", per the V3 permissions docs),
    # but this policy file is the native expression of "the container IS the sandbox"
    # and does not depend on a compatibility flag outliving the transition.
    PERMISSIONS_POLICY = { "rules" => [ { "capability" => "all", "effect" => "allow" } ] }.freeze

    # The 16-byte header every SQLite database starts with, NUL included. Written as an
    # escape rather than a literal NUL so this file stays text.
    SQLITE_MAGIC = "SQLite format 3\u0000"

    # Kiro's control plane, read off the CLI's own traffic through the MITM proxy: a
    # private AWS-JSON 1.0 service, operation in X-Amz-Target, bearer token. Undocumented
    # and not anonymous.
    #
    # This is the V3 service, NOT the CodeWhisperer host the CLI used before it
    # (`codewhisperer.<region>.amazonaws.com`, `AmazonCodeWhispererService.*`). That one
    # still answers GetUsageLimits, but ListAvailableModels on it now returns 403
    # "Your subscription does not support this application" for every `origin` value —
    # the operation moved, the header did not.
    API_HOST_TEMPLATE = "https://management.%<region>s.kiro.dev/"
    API_CONTENT_TYPE = "application/x-amz-json-1.0"
    LIST_MODELS_TARGET = "KiroControlPlaneBearerService.ListAvailableModels"
    USAGE_LIMITS_TARGET = "KiroControlPlaneBearerService.GetUsageLimits"

    # Both operations reject a bare {} body: they want the calling surface and the
    # profile the token is scoped to. `AI_EDITOR` is what the CLI itself sends.
    API_ORIGIN = "AI_EDITOR"

    # Region when the profile ARN carries none. The CLI's own endpoints are pinned to
    # us-east-1, so that is the safer default than guessing from anything else.
    DEFAULT_REGION = "us-east-1"

    # Kiro meters in credits. GetUsageLimits reports the account's credit balance in
    # `usageBreakdownList`, and prices overage credits in real money — which is what
    # turns a credit delta into `cost_cents`.
    CREDIT_RESOURCE_TYPE = "CREDIT"

    # The account's credit counter as of the last session that finished, kept on the
    # credential so the next session can price itself as the movement since then.
    LAST_CREDITS_KEY = "kiro_last_credits"

    # The model catalogue as the CLI reported it, kept on the credential's metadata.
    MODELS_METADATA_KEY = "kiro_models"

    # Where the MITM proxy's capture lands in the artifacts hash #collect_usage is given
    # (see #session_log_paths), and the activity the CLI posts there once per prompt
    # turn with what that turn cost.
    MITM_LOG_KEY = "logs/http.log"
    USAGE_SUMMARY_ACTIVITY = "usageSummary"

    # Kiro's V3 agent only accepts a plain-HTTP MCP server on a loopback host, so the
    # container forwards one to the platform's internal MCP service. The port is
    # arbitrary but fixed: it is written into mcp.json and opened by the watcher.
    MCP_FORWARD_PORT = 4002
    LOOPBACK_HOST = "localhost"
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    # The CLI's own OpenTelemetry counter for what a turn cost, in credits. Exported
    # with DELTA temporality, so batches add up rather than replacing one another —
    # which is exactly what UsageStatistics::Accumulator does with them. Carries `model`
    # and `session_id` as data-point attributes.
    CREDITS_METRIC = "kiro_cli_credits_consumed"
    OTEL_EXPORT_INTERVAL_MS = "2000"

    # Marks a usage row as already priced from the telemetry stream, so cleanup's
    # coarser fallbacks know to leave it alone.
    OTEL_EVENT_SOURCE = "otlp_credits_consumed"

    # USD per credit, from the account's own overage rate. Kept beside the counter so
    # pricing a telemetry batch costs no vendor call.
    CREDIT_RATE_KEY = "kiro_credit_rate_usd"

    # The `state` row holding the CodeWhisperer profile the CLI selected at the end of
    # the login. Its ARN is required on every API call and carries the region they go
    # to, which is NOT the identity-centre region also stored there (`auth.idc.region`
    # was us-west-2 on an account whose profile lives in us-east-1).
    PROFILE_STATE_KEY = "api.codewhisperer.profile"

    def self.default_config_paths
      [ "~/.kiro/settings/mcp.json", "~/.kiro/steering/" ]
    end

    def home_dir
      "/home/kiro"
    end

    # There is no single "config file" holding the credential — #auth_file_paths is what
    # the capture actually reads. This points at the state database so the generic
    # AgentCredentialsService#extract_from_container path still targets the right thing.
    def config_path
      state_path
    end

    def state_path        = "#{home_dir}/#{STATE_PATH}"
    def cli_settings_path = "#{home_dir}/.kiro/settings/cli.json"
    def permissions_path  = "#{home_dir}/.kiro/settings/permissions.yaml"

    # The state database is the whole credential — there is nothing else to capture.
    def auth_file_paths
      [ state_path ]
    end

    def auth_watch_path
      state_path
    end

    # Neither of the watcher's older modes works on this runtime, so it uses the byte
    # marker instead. `__present__` means "the watched file exists and is non-empty",
    # and Kiro's SQLite database is created on the CLI's first run, before the user has
    # seen a device code — the auth terminal would close mid-login. The JSON-key mode
    # cannot parse a binary file at all.
    #
    # What does work is the token payload's own field names. Measured on CLI 2.21.3
    # across all three states of one container:
    #
    #   fresh container, no login    — no marker, no `kirocli:*` row
    #   device code shown, unapproved — `kirocli:odic:device` row, still no marker
    #   login finished                — `access_token` and `refresh_token` present
    #
    # so the marker appears only on success. The row's KEY is not usable for this: it
    # is named after the login method (`kirocli:odic:token` for Builder ID,
    # `kirocli:social:token` for a social login), which is what made an earlier
    # key-name gate discard real credentials. The OAuth field names inside the value
    # do not vary. Both are listed because the watcher ORs them.
    AUTH_MARKERS = %w[__contains__:access_token __contains__:refresh_token].freeze

    def auth_required_keys
      AUTH_MARKERS
    end

    # Server-side twin of the watcher check, run against each captured file. Both
    # halves matter: the content has to be the state database (that database IS the
    # credential), and it has to hold a token. A database captured from a login the
    # user abandoned parses fine and carries only the device registration — persisting
    # it would leave the runtime looking configured while every session starts signed
    # out, which is exactly the failure this runtime shipped with once.
    def auth_complete?(config_content)
      sqlite_blob?(config_content) && contains_token_marker?(config_content)
    end

    # The state database as an opaque base64 blob, plus the whoami payload as a label.
    # Called once per captured file; the results are merged by
    # AgentBaseStrategy#build_credentials_from_files.
    def extract_credentials(config_content)
      return {} if config_content.blank?

      if sqlite_blob?(config_content)
        return { "state_b64" => Base64.strict_encode64(config_content.dup.force_encoding(Encoding::BINARY)) }
      end

      {}
    end

    # Not meaningful for this runtime: the credential is a binary blob, not a document
    # the CLI merges. #config_files is what actually writes the container's state.
    def generate_config(credentials, workflow_config = {})
      credentials
    end

    # Files seeded into a session container before the CLI launches: the login database
    # at the path the CLI reads, and an MCP config for SessionContextService to merge
    # into. User scope (~/.kiro/settings/mcp.json) is loaded for every session, so no
    # custom agent definition is needed to pick the servers up.
    def config_files(credentials, workflow_config = {})
      files = {
        mcp_config_path => { "mcpServers" => {} }.to_json,
        cli_settings_path => CLI_SETTINGS.to_json,
        permissions_path => PERMISSIONS_POLICY.to_yaml
      }

      state = decoded_state(credentials)
      files[state_path] = state if state.present?
      files
    end

    # Seeded before the login runs. The MCP config is not needed to sign in — it is
    # here because writing it creates ~/.kiro, which the login command's marker
    # redirect would otherwise have to `mkdir` for itself. The settings come along so
    # the login terminal does not self-update mid-flow either.
    def auth_setup_files
      {
        mcp_config_path => { "mcpServers" => {} }.to_json,
        cli_settings_path => CLI_SETTINGS.to_json,
        permissions_path => PERMISSIONS_POLICY.to_yaml
      }
    end

    # An interactive session gets the TUI; an automatic one has to be headless, and
    # that is not a preference — it is the only mode in which the prompt arrives.
    #
    # `chat --help` documents a positional `[INPUT]` ("the first question to ask"), and
    # every other runtime here is driven that way: AgentSessionStrategy appends
    # "$AGENT_PROMPT" to the launch command. On V3 the interactive TUI **ignores** it.
    # Measured on 2.21.3 in a real tmux pane, with the trust confirmation pre-answered
    # so nothing else could swallow it: `kiro-cli --v3 chat --trust-all-tools "…"`
    # comes up at an empty "ask a question or describe a task" prompt and waits. A
    # workflow step launched that way never receives its task and sits at `ready` until
    # a watchdog closes it. With `--no-interactive` the same argument is consumed and
    # answered.
    #
    # The cost is that an automatic session has no TUI to attach to — the same trade
    # Antigravity's `--print` makes. Interactive sessions are unaffected: they carry no
    # prompt, so nothing is lost by leaving them in the TUI.
    #
    # `--trust-all-tools` is what makes the container the sandbox, as it is for every
    # other runtime here; its startup confirmation is pre-answered in CLI_SETTINGS.
    def session_command(mode:, prompt: nil, model: nil)
      flags = [ "--trust-all-tools" ]
      flags << "--model #{Shellwords.shellescape(model)}" if model.present?
      flags << "--no-interactive" if mode.to_s == "non_interactive"

      "kiro-cli #{V3_FLAG} chat #{flags.join(' ')}"
    end

    # Context file: a steering document. `~/.kiro/steering/` is loaded on every CLI
    # session in every directory — and on the CLI the `inclusion:` frontmatter modes
    # are ignored, so everything in it is always in context. That keeps /workspace
    # clean, unlike an AGENTS.md, which would have to live in the user's repository.
    def context_file_path
      "#{home_dir}/.kiro/steering/aixle-session-context.md"
    end

    # skills.sh agent id for `npx skills add --agent kiro-cli`.
    def skills_agent_name
      "kiro-cli"
    end

    # Where `skills add -g -a kiro-cli` puts a skill. Kiro implements the open Agent
    # Skills standard, so a SKILL.md written here is discovered unchanged.
    def skills_install_path
      "#{home_dir}/.kiro/skills"
    end

    def mcp_config_path
      "#{home_dir}/.kiro/settings/mcp.json"
    end

    # MCP config: merged into ~/.kiro/settings/mcp.json. Kiro infers the transport from
    # which fields are present — `command` for stdio, `url` for remote HTTP/SSE — so
    # there is no type field. Remote servers take a `headers` map, which is how the
    # internal aixle-tools server receives its bearer token.
    def mcp_config(servers)
      mcp_servers = servers.each_with_object({}) do |s, acc|
        entry = {}
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args) && s.args.present?
          env = mcp_stdio_env(s)
          entry["env"] = env if env.present?
        else
          entry["url"] = loopback_url(s.url) if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        entry["disabled"] = false
        acc[MCPServer.config_key_for(s.name)] = entry
      end

      { mcp_config_path => { "mcpServers" => mcp_servers }.to_json }
    end

    def mcp_merge_strategy
      :merge_json
    end

    # A KIRO_API_KEY left in the environment is a credential for a different account,
    # and this runtime never holds one — every login here is the device-code flow.
    def conflicting_env_keys(_credentials)
      %w[KIRO_API_KEY]
    end

    # =================================================================
    # Available Models
    # =================================================================

    # The catalogue is per account and Kiro's published model list disagrees with it, so
    # a hard-coded list would be wrong for real users: this asks the account. Whatever
    # the CLI captured most recently wins, because that is the list the account's own
    # sessions will actually accept; the API answers for a credential that has no
    # capture yet. The CLI's JSON is snake_case and the API's camelCase — #model_entry
    # reads both.
    def fetch_available_models(credentials, credential: nil)
      cached = Array(credential&.metadata&.dig(MODELS_METADATA_KEY))
      return cached.filter_map { |model| model_entry(model) } if cached.present?

      body = api_call(credentials, LIST_MODELS_TARGET)
      return [] if body.blank?

      models = Array(body["models"])
      models = [ body["defaultModel"] ].compact if models.empty?
      models.filter_map { |model| model_entry(model) }
    end

    # Facts worth keeping on the credential that a container is the cheapest place to
    # learn: the catalogue as the CLI reports it (already in the shape its own sessions
    # accept), and — at login only — the credit counter this account starts from.
    def collect_credential_metadata(runtime, container, credential, phase)
      extras = {}

      command = [ "kiro-cli", V3_FLAG, "chat", "--list-models", "--format", "json" ]
      stdout, _stderr, status = runtime.exec(container, command, stdout: true, stderr: true)
      if status.to_i.zero?
        models = Array(parse_json(Array(stdout).join)["models"]).select { |m| m.is_a?(Hash) && model_id_of(m).present? }
        extras[MODELS_METADATA_KEY] = models if models.any?
      end

      phase == :auth ? extras.merge(seeded_credit_baseline(credential)) : extras
    rescue StandardError => e
      Rails.logger.warn("[KiroCliAdapter] could not read the model catalogue: #{e.class}: #{e.message}")
      {}
    end

    # Cost is a delta, so the very first session has nothing to subtract from and would
    # report no cost at all. Seed the baseline at login, and only at login: from then on
    # #collect_usage owns the key, and this hook runs BEFORE it during session cleanup —
    # writing the current reading here would make that very session measure zero.
    def seeded_credit_baseline(credential)
      return {} if credential.blank? || credential.metadata&.key?(LAST_CREDITS_KEY)

      usage = credit_usage(credential.config_data)
      return {} if usage.blank?

      { LAST_CREDITS_KEY => usage[:used], CREDIT_RATE_KEY => usage[:rate_usd] }
    end

    # =================================================================
    # Usage / cost
    # =================================================================

    # Credits the account has spent so far this billing period, and what a credit is
    # worth. Kiro publishes no per-request token counts, so a session's cost is the
    # movement of this counter across the session (see #collect_usage).
    def credit_usage(credentials)
      body = api_call(credentials, USAGE_LIMITS_TARGET)
      return nil if body.blank?

      breakdown = Array(body["usageBreakdownList"]).find { |b| b["resourceType"] == CREDIT_RESOURCE_TYPE }
      return nil if breakdown.blank?

      credit_breakdown(body)
    end

    # The same reading, in the shape the profile's usage card speaks
    # (Agents::SubscriptionUsageService). Kiro has no rolling windows like Claude's
    # five-hour bucket: it has one credit allowance per billing period, so that is the
    # single "window", carrying the raw counts as well as the percentage — a plan
    # measured in credits is most useful as "N of M left", not as a bare percentage.
    def fetch_subscription_usage(credentials)
      body = api_call(credentials, USAGE_LIMITS_TARGET)
      return { status: "unavailable" } if body.blank?

      usage = credit_breakdown(body)
      return { status: "unavailable" } if usage.blank?

      { status: "ok", windows: [ credit_window(usage, body) ], extra_usage: overage_usage(body) }
    end

    # Cost comes from the credit counter moving, not from token counts — Kiro emits
    # none outside headless stream-json.
    #
    # Two sources, in this order.
    #
    # The CLI reports its own spend. Every turn it posts a `usageSummary` activity to
    # `runtime.<region>.kiro.dev/agents/activity` carrying `promptTurnSummaries[].usage`
    # in credits, and the MITM proxy already captures it. That is exact and it is this
    # session's alone.
    #
    # Without that log — MITM off, or a session that produced no turns — the fallback is
    # the movement of the account's credit counter since the previous reading. It agreed
    # with the CLI's own figure to four decimal places on a measured session (0.5174
    # credits), but it is per ACCOUNT: a concurrent session, or the user working in the
    # Kiro IDE, lands in the same number. So it is the fallback, not the source.
    # Price a batch of the CLI's own telemetry. Called by UsageStatisticsService for
    # every OTLP payload whose resource carries this session's token.
    #
    # This is the primary cost source for the runtime: `kiro_cli_credits_consumed` is
    # what the CLI itself charged the account for this session, per turn, with the model
    # attached — exact, attributable, and free of the account-wide contamination the
    # credit-counter fallback suffers from. The metric is DELTA, so each batch is new
    # spend and the accumulator adds it.
    def ingest_usage(payload, terminal_session)
      events = otlp_credit_events(payload, terminal_session)
      return :accepted if events.empty?

      UsageStatistics::Accumulator.record(
        terminal_session: terminal_session, events: events, source: "kiro_credits"
      )
    end

    def collect_usage(terminal_session, artifacts = {})
      credential = SessionCompany.agent_credentials_for(terminal_session).find_by(agent_type: "kiro_cli")
      usage = credit_usage(credential&.config_data || {})
      previous = credential&.metadata&.dig(LAST_CREDITS_KEY)

      # Advance the counter even when something else carries the cost, so the next
      # session's fallback still has a fresh baseline to subtract from — and keep the
      # rate the telemetry path prices with current.
      if usage.present? && credential.present?
        credential.update_column(:metadata, (credential.metadata || {}).merge(
          LAST_CREDITS_KEY => usage[:used], CREDIT_RATE_KEY => usage[:rate_usd]
        ))
      end

      # The CLI's telemetry is the accurate source and it has been streaming in all
      # session. If it priced this session, nothing coarser may touch the row.
      if priced_by_telemetry?(terminal_session)
        Rails.logger.info("[KiroCliAdapter] session #{terminal_session.id}: already priced from telemetry")
        return
      end

      turns = turn_summaries(artifacts[MITM_LOG_KEY])
      if turns.any?
        record_credit_usage(terminal_session, credential, usage,
                            credits: turns.sum { |t| t[:credits] },
                            events: turns,
                            source: "agent_activity_usage_summary")
        return
      end

      if usage.blank?
        Rails.logger.info("[KiroCliAdapter] session #{terminal_session.id}: no turn summaries and no credit reading, leaving cost unset")
        return
      end

      if previous.blank?
        Rails.logger.info("[KiroCliAdapter] session #{terminal_session.id}: first reading (#{usage[:used]} credits), no delta yet")
        return
      end

      record_credit_usage(terminal_session, credential, usage,
                          credits: [ usage[:used] - previous.to_f, 0.0 ].max,
                          events: [],
                          source: "get_usage_limits_delta")
    end

    # The MITM proxy records the CLI's own calls to the Kiro service. Nothing parses
    # them yet — they are collected so the per-request `creditsUsed` in
    # SendTelemetryEvent can be read from real traffic before any parser is written.
    # Kiro's CLI exports OpenTelemetry, and where it exports to is configurable — so the
    # platform points it at its own collector, the same one Claude Code reports into.
    # `OTEL_RESOURCE_ATTRIBUTES` is honoured by its SDK (verified against 2.21.3), which
    # is what lets UsageStatisticsService route a batch back to this session.
    #
    # Redirecting it is also what keeps a customer's session out of Kiro's analytics:
    # the export's default target is the vendor's own collector, so pointing it here
    # moves that traffic rather than copying it. `KIRO_DISABLE_TELEMETRY` is deliberately
    # not set — measured, it stops this export too, taking the cost figures with it.
    def default_env_vars(session)
      {
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => mitm_tracked_domains.join(","),
        # Opens 127.0.0.1:MCP_FORWARD_PORT onto the platform's MCP service, which is
        # what makes the loopback URL in mcp.json resolve. See #loopback_url.
        "MCP_FORWARD_PORT" => MCP_FORWARD_PORT.to_s,
        "MCP_FORWARD_TARGET" => mcp_forward_target,
        "KIRO_TELEMETRY_OTEL" => "1",
        "KIRO_TELEMETRY_OTLP_ENDPOINT" => Settings.otel.endpoint,
        "KIRO_TELEMETRY_EXPORT_INTERVAL_MS" => OTEL_EXPORT_INTERVAL_MS,
        "OTEL_RESOURCE_ATTRIBUTES" => "terminal_session_token=#{session&.route_token}"
      }.compact_blank
    end

    def mitm_tracked_domains
      %w[amazonaws.com kiro.dev]
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    private

    # The bearer token and profile ARN, read out of the stored state database on demand
    # rather than copied into the credential beside it. The blob is the single source of
    # truth and it is re-captured at every session cleanup (the CLI refreshes its own
    # token in the container), so a stored copy would only ever be a staler duplicate of
    # a secret we already hold.
    #
    # The two halves live in two different tables, and both are needed: `auth_kv` holds
    # the token, while the profile ARN — which every API call must carry, and which
    # names the region those calls go to — is a row in `state` under
    # PROFILE_STATE_KEY. Reading only the token yields a record the API rejects.
    #
    # The auth_kv row key depends on how the user signed in — Builder ID writes
    # `kirocli:odic:token`, a social login `kirocli:social:token` — so every row is read
    # and the one carrying an access token wins, rather than matching a name.
    def auth_record(blob)
      return {} if blob.blank?

      Tempfile.create([ "kiro-state", ".sqlite3" ]) do |file|
        file.binmode
        file.write(blob)
        file.flush

        SQLite3::Database.new(file.path, readonly: true) do |db|
          token = token_row(db)
          return {} if token.blank?

          return token.merge("profile_arn" => profile_arn_from(db)).compact
        end
      end
      {}
    rescue SQLite3::Exception => e
      Rails.logger.warn("[KiroCliAdapter] could not read the state database: #{e.class}: #{e.message}")
      {}
    end

    def token_row(db)
      db.execute("SELECT value FROM auth_kv").each do |(value)|
        parsed = parse_json(value)
        return parsed if parsed.is_a?(Hash) && parsed["access_token"].present?
      end
      nil
    end

    # `{"arn":"arn:aws:codewhisperer:us-east-1:…:profile/XXXX","profile_name":"…"}`,
    # written when the CLI fetches profiles at the end of the login.
    def profile_arn_from(db)
      row = db.execute("SELECT value FROM state WHERE key = ?", [ PROFILE_STATE_KEY ]).first
      parse_json(row&.first).then { |parsed| parsed.is_a?(Hash) ? parsed["arn"].presence : nil }
    rescue SQLite3::Exception
      nil
    end

    # AWS-JSON 1.0: one POST, the operation in a header, the payload in the body.
    # Returns the parsed body, or nil for anything that is not a clean 200 — an expired
    # access token is an ordinary outcome here (the CLI refreshes its own token inside
    # the container, and the session cleanup re-captures it), not an error to raise on.
    def api_call(credentials, target)
      record = auth_record(decoded_state(credentials))
      token = record["access_token"]
      profile_arn = record["profile_arn"]
      return nil if token.blank? || profile_arn.blank?

      uri = URI(format(API_HOST_TEMPLATE, region: region_from(profile_arn)))
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = API_CONTENT_TYPE
      request["X-Amz-Target"] = target
      request["Authorization"] = "Bearer #{token}"
      request.body = { origin: API_ORIGIN, profileArn: profile_arn }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[KiroCliAdapter] #{target} returned #{response.code}: #{response.body.to_s.truncate(200)}")
        return nil
      end

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.warn("[KiroCliAdapter] #{target} failed: #{e.class}: #{e.message}")
      nil
    end

    # A profile ARN carries the region it belongs to
    # (arn:aws:codewhisperer:us-east-1:...), which is the region its API calls have to
    # go to.
    def region_from(profile_arn)
      part = profile_arn.to_s.split(":")[3]
      part.presence || DEFAULT_REGION
    end

    # What a model costs and what it can take, in one line for the picker. Kiro prices
    # in credit multipliers rather than per-token money.
    # Kiro's V3 agent refuses a plain-HTTP MCP server unless its host is loopback —
    # "host must be 127.0.0.1 or localhost, got `web`", from the CLI's own source — and
    # it refuses it silently: the server simply never appears in the agent's tool list,
    # which is how a session ends up unable to call `finish_session`.
    #
    # Every deployment of this platform serves MCP over internal HTTP
    # (`http://web:4002/action_mcp` in development, `http://mcp.<ns>.svc.cluster.local:4002`
    # in staging and production), so this affects all of them. Rather than terminate TLS
    # on an internal hop, the agent container forwards a loopback port to that address
    # (the watcher's MCP_FORWARD_* support) and the URL written into mcp.json points at
    # the loopback end. Same bytes, same destination, a host Kiro will accept.
    #
    # An HTTPS URL, or one that is already loopback, is passed through untouched.
    def loopback_url(url)
      uri = URI.parse(url.to_s)
      return url unless forwardable_uri?(uri)

      uri.host = LOOPBACK_HOST
      uri.port = MCP_FORWARD_PORT
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def forwardable_uri?(uri)
      uri.scheme == "http" && uri.host.present? && !LOOPBACK_HOSTS.include?(uri.host)
    end

    # The upstream the container forwards to, as "host:port", or nil when the configured
    # MCP URL needs no forwarding.
    def mcp_forward_target
      uri = URI.parse(Settings.mcp.server_url.to_s)
      return nil unless forwardable_uri?(uri)

      "#{uri.host}:#{uri.port || 80}"
    rescue URI::InvalidURIError, NoMethodError
      nil
    end

    def priced_by_telemetry?(terminal_session)
      stat = terminal_session.usage_statistic
      return false if stat.blank?

      Array(stat.events_data).any? { |event| event.is_a?(Hash) && event["source"] == OTEL_EVENT_SOURCE }
    end

    def otlp_credit_events(payload, terminal_session)
      token = terminal_session.route_token
      return [] if token.blank?

      rate = credit_rate_for(terminal_session)

      Array(payload["resourceMetrics"]).flat_map do |resource_metric|
        resource_attrs = resource_metric.dig("resource", "attributes") || []
        next [] unless otlp_attribute(resource_attrs, "terminal_session_token") == token

        Array(resource_metric["scopeMetrics"]).flat_map do |scope_metric|
          Array(scope_metric["metrics"]).flat_map do |metric|
            next [] unless metric["name"] == CREDITS_METRIC

            otlp_credit_data_points(metric).filter_map { |point| otlp_credit_event(point, rate) }
          end
        end
      end
    end

    # Only a monotonic delta sum is safe to add up. Anything else would be a shape the
    # CLI has never sent, and guessing at it is how a cost figure silently doubles.
    def otlp_credit_data_points(metric)
      sum = metric["sum"]
      return [] unless sum.is_a?(Hash)
      return [] unless sum["aggregationTemporality"].to_s.end_with?("DELTA")

      Array(sum["dataPoints"])
    end

    def otlp_credit_event(point, rate)
      credits = (point["asDouble"] || point["asInt"]).to_f
      return nil if credits.zero?

      attrs = point["attributes"] || []
      model = otlp_attribute(attrs, "model")
      timestamp_ns = point["timeUnixNano"]

      {
        # Kiro publishes no token counts, so the only figure here is money. The CLI
        # sends the literal "unknown" when a turn ran on the account default.
        "model" => (model if model.present? && model != "unknown"),
        "timestamp" => timestamp_ns.presence && (timestamp_ns.to_i / 1_000_000).to_s,
        "tokenUsage" => { "totalCents" => (credits * rate * 100).round(6) },
        "creditsUsed" => credits.round(6),
        "creditRateUsd" => rate,
        "kiroSessionId" => otlp_attribute(attrs, "session_id"),
        "requestId" => otlp_attribute(attrs, "request_id"),
        "source" => OTEL_EVENT_SOURCE
      }.compact
    end

    def otlp_attribute(attributes, key)
      entry = Array(attributes).find { |a| a.is_a?(Hash) && a["key"] == key }
      entry&.dig("value", "stringValue")
    end

    # The rate is written onto the credential whenever the account's limits are read
    # (at login, and at every cleanup). A batch that arrives before the first reading
    # still records its credits — it just prices them at zero rather than guessing.
    def credit_rate_for(terminal_session)
      credential = SessionCompany.agent_credentials_for(terminal_session).find_by(agent_type: "kiro_cli")
      credential&.metadata&.dig(CREDIT_RATE_KEY).to_f
    rescue StandardError
      0.0
    end

    # Credits the CLI itself reported for this session, one entry per prompt turn.
    #
    # The turns are posted to `/agents/activity` as they happen and the MITM proxy logs
    # each request as a JSON line; the payload is a batch of activities, of which
    # `usageSummary` is the one that carries money. Anything unparseable is skipped
    # rather than raised on — a truncated or rotated log should cost a cost figure, not
    # the session.
    def turn_summaries(mitm_log)
      return [] if mitm_log.blank?

      mitm_log.each_line.flat_map { |line| activity_usage_summaries(line) }
    end

    def activity_usage_summaries(line)
      return [] unless line.include?(USAGE_SUMMARY_ACTIVITY)

      payload = parse_json(parse_json(line)["body"].to_s)
      Array(payload["payload"]).filter_map do |activity|
        next unless activity.is_a?(Hash) && activity["activityType"] == USAGE_SUMMARY_ACTIVITY

        summaries = Array(activity.dig("content", "promptTurnSummaries"))
        credits = summaries.sum { |s| s["usage"].to_f }
        next if credits.zero?

        {
          credits: credits,
          status: activity.dig("content", "status"),
          elapsed_ms: activity.dig("content", "elapsedTime"),
          tools: summaries.flat_map { |s| Array(s["usedTools"]) }.uniq
        }
      end
    end

    # One shape for both sources, so a session priced either way reads the same.
    def record_credit_usage(terminal_session, credential, usage, credits:, events:, source:)
      rate = usage&.dig(:rate_usd).to_f
      cents = credits * rate * 100

      stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic
      stat.assign_attributes(
        # Kiro publishes no token counts outside headless stream-json.
        input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0,
        total_cents_precise: cents,
        cost_cents: cents.ceil,
        # There are no per-model counts to break the cost down by — Kiro bills one
        # credit pool — so this records which model the session ran on, which is what
        # the session page's "Models" card is for.
        models: [ session_model(terminal_session, credential) ].compact,
        source: "kiro_credits",
        events_count: [ events.size, 1 ].max,
        events_data: credit_events_data(credits, rate, usage, events, source)
      )
      stat.save!

      Rails.logger.info(
        "[KiroCliAdapter] session #{terminal_session.id}: #{credits.round(4)} credits " \
        "via #{source} => #{cents.round(4)} cents"
      )
    end

    def credit_events_data(credits, rate, usage, events, source)
      return [ credit_event(credits, rate, usage, source) ] if events.empty?

      events.map do |event|
        credit_event(event[:credits], rate, usage, source).merge(
          "status" => event[:status], "elapsedMs" => event[:elapsed_ms], "usedTools" => event[:tools]
        ).compact
      end
    end

    def credit_event(credits, rate, usage, source)
      {
        "creditsUsed" => credits.round(6),
        "creditRateUsd" => rate,
        "planLimitCredits" => usage&.dig(:limit),
        "plan" => usage&.dig(:plan),
        "source" => source
      }.compact
    end

    # What the session actually ran on: its own request if it made one, else the model
    # pinned on the credential — the same order AgentSessionStrategy#resolve_model uses
    # to build the launch command.
    def session_model(terminal_session, credential)
      terminal_session.requested_model.presence || credential&.default_model.presence
    end

    # The CLI answers in snake_case and the API in camelCase, for the same fields.
    def model_id_of(model)    = (model["model_id"] || model["modelId"]).presence
    def model_name_of(model)  = (model["model_name"] || model["modelName"]).presence
    def rate_multiplier_of(model) = model["rate_multiplier"] || model["rateMultiplier"]
    def rate_unit_of(model)   = model["rate_unit"] || model["rateUnit"]

    # Context window: a number from the CLI, a nested limits object from the API.
    def context_window_of(model)
      model["context_window_tokens"] || model.dig("tokenLimits", "maxInputTokens")
    end

    def model_entry(model)
      return nil unless model.is_a?(Hash)

      id = model_id_of(model)
      return nil if id.blank?

      { model_id: id, display_name: model_name_of(model) || id, description: model_description(model) }
    end

    def model_description(model)
      parts = []
      multiplier = rate_multiplier_of(model)
      parts << "#{multiplier}x #{(rate_unit_of(model) || 'credit').downcase}s" if multiplier.present?
      context = context_window_of(model)
      parts << "#{context} input tokens" if context.present?
      parts << model["description"] if model["description"].present?
      parts.join(" · ").truncate(120)
    end

    # The CREDIT row of a GetUsageLimits body. The `…WithPrecision` fields are the real
    # numbers; their plain counterparts are rounded to whole credits and read 0 for a
    # session that spent less than one.
    def credit_breakdown(body)
      breakdown = Array(body["usageBreakdownList"]).find { |b| b["resourceType"] == CREDIT_RESOURCE_TYPE }
      return nil if breakdown.blank?

      {
        used: (breakdown["currentUsageWithPrecision"] || breakdown["currentUsage"]).to_f,
        limit: (breakdown["usageLimitWithPrecision"] || breakdown["usageLimit"]).to_f,
        rate_usd: breakdown["overageRate"].to_f,
        plan: body.dig("subscriptionInfo", "subscriptionTitle")
      }
    end

    def credit_window(usage, body)
      {
        key: "kiro_credits",
        utilization: usage[:limit].positive? ? (usage[:used] / usage[:limit] * 100).round(2) : 0.0,
        resets_at: epoch_to_iso(body["nextDateReset"]),
        used: usage[:used].round(2),
        limit: usage[:limit].round(2),
        unit: "credits",
        plan: usage[:plan]
      }.compact
    end

    # Pay-as-you-go on top of the plan. Kiro reports it as OverageConfiguration, and an
    # account with it switched off still carries a cap — reporting that as a live limit
    # would read as headroom the user does not have.
    def overage_usage(body)
      return nil unless body.dig("overageConfiguration", "overageStatus") == "ENABLED"

      breakdown = Array(body["usageBreakdownList"]).find { |b| b["resourceType"] == CREDIT_RESOURCE_TYPE }
      return nil if breakdown.blank?

      cap = (breakdown["overageCapWithPrecision"] || breakdown["overageCap"]).to_f
      used = (breakdown["currentOveragesWithPrecision"] || breakdown["currentOverages"]).to_f

      {
        enabled: true,
        utilization: cap.positive? ? (used / cap * 100).round(2) : nil,
        monthly_limit: cap,
        used_credits: used.round(2)
      }
    end

    # Kiro sends reset times as a float epoch.
    def epoch_to_iso(value)
      return nil if value.blank?

      Time.at(value.to_f).utc.iso8601
    rescue StandardError
      nil
    end

    def sqlite_blob?(content)
      return false if content.blank?

      content.to_s.dup.force_encoding(Encoding::BINARY)
             .start_with?(SQLITE_MAGIC.dup.force_encoding(Encoding::BINARY))
    end

    # Same test the watcher runs in the container, on the same bytes: the token
    # payload's OAuth field names, read out of AUTH_MARKERS so the two cannot drift.
    def contains_token_marker?(content)
      binary = content.to_s.dup.force_encoding(Encoding::BINARY)

      AUTH_MARKERS.any? do |key|
        binary.include?(key.delete_prefix("__contains__:").dup.force_encoding(Encoding::BINARY))
      end
    end

    def decoded_state(credentials)
      blob = credentials.is_a?(Hash) ? credentials["state_b64"] : nil
      return nil if blob.blank?

      Base64.strict_decode64(blob)
    rescue ArgumentError => e
      Rails.logger.warn("[KiroCliAdapter] stored state is not valid base64: #{e.message}")
      nil
    end
  end
end
