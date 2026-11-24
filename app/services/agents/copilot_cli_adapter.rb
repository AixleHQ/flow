# frozen_string_literal: true

require "json"
require "shellwords"

module Agents
  # GitHub Copilot CLI adapter (`@github/copilot`, binary `copilot`).
  #
  # Container layout ($COPILOT_HOME = ~/.copilot, set by the image):
  #   config.json              — state the CLI manages: trusted folders, signed-in
  #                              accounts and, with no keychain in the image, their tokens.
  #                              It is JSON with `//` comment lines at the top.
  #   settings.json            — user settings (storeTokenPlaintext, auto-switch on limits…).
  #   mcp-config.json          — user-level MCP servers.
  #   copilot-instructions.md  — personal instructions, read in every directory: the
  #                              session context lands here.
  #   skills/                  — where `skills add -g -a github-copilot` installs.
  #   aixle-token              — the stored token, handed to the CLI by the session command.
  #
  # Auth: the auth terminal runs `copilot login --device-code` (AgentBaseStrategy::AUTH_COMMANDS),
  # which leaves the token in config.json, where it is captured. A Microsoft Entra
  # account is not offered there: the CLI keeps that sign-in behind its own flag and an
  # OS broker or a browser callback on the container's localhost
  # (docs/design/copilot-cli-runtime.md).
  # Sessions never get the token in config.json or in the container's environment:
  # #session_command exports COPILOT_GITHUB_TOKEN from a 0600 file, because that variable
  # outranks GH_TOKEN, GITHUB_TOKEN and the stored login, so nothing a project or the
  # image puts in the environment can replace the user's own account.
  class CopilotCliAdapter < BaseAdapter
    COPILOT_DIR = ".copilot"
    TOKEN_FILE = "aixle-token"
    WORKSPACE = "/workspace"

    # The key `copilot login` writes its tokens under; config.json has it only once a
    # login has completed (measured on 1.0.108: absent while the one-time code is shown).
    AUTH_MARKER = '"authTokens"'

    # Token prefixes the CLI accepts. A classic PAT (ghp_) is refused by the CLI itself.
    TOKEN_PATTERN = /\A(?:gho_|ghu_|github_pat_)[A-Za-z0-9_]{20,}\z/

    # Account kinds that sign in with a GitHub token. `copilot login` also knows Microsoft
    # Entra accounts, whose tokens this adapter does not handle.
    GITHUB_ACCOUNT_KINDS = %w[githubDotCom proxima].freeze
    DEFAULT_HOST = "https://github.com"

    # Settings every container starts with. `storeTokenPlaintext` answers the "store the
    # token in plaintext?" question `copilot login` asks when there is no keychain, which
    # the image never has. `continueOnAutoMode` switches to Auto on a model's rate limit
    # instead of asking "Switch to …?", a question a non_interactive session cannot answer.
    #
    # `toolSearch` and `dynamicRetrieval.mcp` off keep the MCP tools in the model's own tool
    # list. With a project's full tool set the CLI otherwise defers them behind a search
    # tool: on staging an automatic session found `aixle-tools-finish_session` there, called
    # `finish_session` instead, was told it does not exist, and never finished.
    SETTINGS = {
      "storeTokenPlaintext" => true,
      "autoUpdate" => false,
      "banner" => "never",
      "continueOnAutoMode" => true,
      "toolSearch" => false,
      "dynamicRetrieval" => { "mcp" => false }
    }.freeze

    MODELS_METADATA_KEY = "copilot_models"
    DEFAULT_MODEL_METADATA_KEY = "copilot_default_model"
    MODELS_SCRIPT = "/opt/aixle/copilot-models.mjs"
    FALLBACK_MODELS = [
      { model_id: "auto", display_name: "Auto", description: "Let Copilot pick the best model" }
    ].freeze

    OTEL_SOURCE = "otlp_copilot"
    TRANSCRIPT_SOURCE = "copilot_transcript"
    TRANSCRIPT_SUFFIX = ".events.jsonl"
    # Set on the session once cleanup has counted the calls OTLP did not deliver
    # (#collect_usage); a span that arrives after it is already counted.
    RECONCILED_KEY = "usage_reconciled_at"
    CHAT_OPERATION = "chat"
    NANO_AIU_PER_CREDIT = 1_000_000_000.0

    def self.default_config_paths
      [ "~/.copilot/config.json", "~/.copilot/copilot-instructions.md" ]
    end

    def home_dir
      "/home/copilot"
    end

    def copilot_dir    = "#{home_dir}/#{COPILOT_DIR}"
    def config_path    = "#{copilot_dir}/config.json"
    def settings_path  = "#{copilot_dir}/settings.json"
    def token_path     = "#{copilot_dir}/#{TOKEN_FILE}"
    def mcp_config_path = "#{copilot_dir}/mcp-config.json"

    def auth_file_paths
      [ config_path ]
    end

    def auth_required_keys
      [ "__contains__:#{AUTH_MARKER}" ]
    end

    def auth_complete?(config_content)
      login_token(parse_config(config_content)).present?
    end

    # The token and whose it is. Nothing else from config.json is kept: trust, MCP and
    # model settings are rendered for every session, so a change to the CLI's own state
    # format can never corrupt a stored credential.
    def extract_credentials(config_content)
      login = login_token(parse_config(config_content))
      return {} if login.nil?

      login.merge("source" => token_source(login["token"]))
    end

    def generate_config(_credentials, _workflow_config = {})
      { "trustedFolders" => [ WORKSPACE ] }
    end

    def config_files(credentials, workflow_config = {})
      files = {
        config_path => generate_config(credentials, workflow_config).to_json,
        settings_path => SETTINGS.to_json
      }
      files.merge(credential_files(credentials))
    end

    def credential_files(credentials)
      token = credentials.is_a?(Hash) ? credentials["token"] : nil
      token.present? ? { token_path => token } : {}
    end

    def private_file_paths
      [ token_path ]
    end

    # Written before `copilot login` starts (AgentAuthStrategy#before_exec), so it stores
    # its token without asking. config.json is left to the CLI: it is the file the login
    # is captured from.
    def auth_setup_files
      { settings_path => SETTINGS.to_json }
    end

    def credential_identity(credentials)
      return nil unless credentials.is_a?(Hash) && credentials["login"].present?

      "#{credentials['host'] || DEFAULT_HOST}:#{credentials['login']}"
    end

    # The TUI in both modes, so the live terminal shows the agent working. An automatic
    # session gets its prompt through `-i`, which AgentSessionStrategy fills by appending
    # the prompt file's contents, and loses the ask_user tool, whose question form nobody
    # would answer.
    #
    # The token is read from its file in the shell that starts the CLI, not passed in
    # the container's environment, where a pod spec or `docker inspect` would show it;
    # `--secret-env-vars` then keeps it out of the shells and MCP servers the CLI starts.
    # The built-in GitHub MCP server is off: it would act with the user's own token across
    # all of GitHub, while the session's repositories are already reachable through the
    # platform's git and gh setup.
    # Resume, measured 2026-11-20: the session directory alone is enough, and the
    # command keeps #session_command's token prefix, without which the CLI asks for /login.
    def conversation_paths = [ "#{COPILOT_DIR}/session-state" ]
    def conversation_id_command = "ls -td #{COPILOT_DIR}/session-state/*/ 2>/dev/null | head -1 | xargs -r basename"
    def resume_arguments(id) = "--resume=#{id}"

    def session_command(mode:, model: nil, effort: nil)
      parts = [
        %(COPILOT_GITHUB_TOKEN="$(cat #{token_path})"),
        "copilot", "--allow-all", "--no-auto-update", "--disable-builtin-mcps",
        "--secret-env-vars=COPILOT_GITHUB_TOKEN"
      ]
      parts += [ "--model", Shellwords.shellescape(model) ] if model.present?
      parts += [ "--reasoning-effort", Shellwords.shellescape(effort) ] if effort.present?
      parts << "--no-ask-user" if mode.to_s == "non_interactive"
      parts.join(" ")
    end

    # `-i` runs the prompt and keeps the TUI (an automatic session ends by finish_session).
    def prompt_argument(prompt) = "-i #{prompt}"

    def context_file_path
      "#{copilot_dir}/copilot-instructions.md"
    end

    def skills_agent_name
      "github-copilot"
    end

    def skills_install_path
      "#{copilot_dir}/skills"
    end

    def mcp_config(servers)
      mcp_servers = servers.to_h do |s|
        entry = { "type" => mcp_type(s.transport), "tools" => [ "*" ] }
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args)
          entry["env"] = mcp_stdio_env(s)
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        [ MCPServer.config_key_for(s.name), entry ]
      end
      { mcp_config_path => { "mcpServers" => mcp_servers }.to_json }
    end

    # The CLI's OpenTelemetry export goes to the platform's collector: its traces carry
    # each model call's AI credits (#ingest_usage), and OTEL_RESOURCE_ATTRIBUTES, which
    # it honours (measured on 1.0.108), routes a batch back to this session.
    # COPILOT_GH_HOST pins the host the token belongs to, so a GH_HOST a project sets for
    # its own tools cannot send the login elsewhere.
    #
    # `callbacks` are the session's callback addresses where its runtime hands them over
    # (external runners); without them the session is hosted and reports to the platform's
    # collector. A session with no collector to reach exports nothing.
    def default_env_vars(session, callbacks: nil)
      credential = session && SessionCompany.agent_credentials_for(session).find_by(agent_type: "copilot_cli")
      otel = callbacks ? callbacks[:otel] : Settings.otel.endpoint.to_s
      content = otel.present? && session&.full_telemetry?
      {
        "COPILOT_OTEL_ENABLED" => otel.present? ? "true" : nil,
        "OTEL_EXPORTER_OTLP_ENDPOINT" => otel,
        "OTEL_EXPORTER_OTLP_PROTOCOL" => otel.present? ? "http/json" : nil,
        "OTEL_RESOURCE_ATTRIBUTES" => session && UsageStatistics::SessionKey.resource_attributes(session),
        # Message content on the spans, with full telemetry (TerminalSession#full_telemetry?,
        # docs/design/agent-telemetry.md): prompts, replies, system instructions, tool
        # definitions, arguments and results. The legacy switch is the one 1.0.108
        # documents; the newer one is set too in case it is honoured.
        "OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT" => content ? "true" : nil,
        "OTEL_INSTRUMENTATION_GENAI_CAPTURE_CONTENT" => content ? "SPAN_AND_EVENT" : nil,
        "COPILOT_GH_HOST" => gh_host(credential&.config_data)
      }.compact_blank
    end

    # The account's catalogue is not published anywhere the platform can ask with a
    # token, so it is read from the CLI in the container (#collect_credential_metadata);
    # until then the picker offers Auto alone.
    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(_credentials, credential: nil)
      # The CLI's catalogue can list `auto` twice (measured on a Business seat, 1.0.108).
      models = Array(credential&.metadata&.dig(MODELS_METADATA_KEY)).filter_map { |model| model_entry(model) }
                                                                  .uniq { |model| model[:model_id] }
      return { models: models, source: :api } if models.any?

      { models: FALLBACK_MODELS.map(&:dup), source: :fallback }
    end

    def collect_credential_metadata(runtime, container, _credential, _phase)
      stdout, _stderr, status = runtime.exec(container, [ "node", MODELS_SCRIPT ], stdout: true, stderr: true)
      return {} unless status.to_i.zero?

      body = parse_json(Array(stdout).join)
      models = Array(body["models"]).select { |m| m.is_a?(Hash) && m["id"].present? }
      return {} if models.empty?

      { MODELS_METADATA_KEY => models, DEFAULT_MODEL_METADATA_KEY => body["default_model"] }.compact
    rescue StandardError => e
      Rails.logger.warn("[CopilotCliAdapter] could not read the model catalogue: #{e.class}: #{e.message}")
      {}
    end

    # One event per model call: the CLI's `chat` spans each carry the call's tokens and
    # the AI credits GitHub charged for it (github.copilot.nano_aiu, 10^9 per credit). The
    # `invoke_agent` span that wraps a turn repeats the turn's total, so it is skipped
    # rather than added on top.
    def ingest_usage(payload, terminal_session)
      return :accepted if terminal_session.metadata.to_h[RECONCILED_KEY].present?

      events = otlp_chat_events(payload, terminal_session)
      return :accepted if events.empty?

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: events, source: OTEL_SOURCE)
    end

    # The CLI exports its spans on a timer, and the container is stopped soon after
    # finish_session, so the spans of a session's last calls never leave it: 2 of 4 calls
    # arrived for a step on 2026-11-18, none for a 10-second one. Its transcript records
    # every call (`session.usage_record`) with the same tokens and AI credits, so cleanup
    # counts the calls OTLP did not deliver. The session is marked first, so a span that
    # arrives from then on is dropped instead of counted a second time.
    def collect_usage(terminal_session, artifacts = {})
      transcript = artifacts.select { |name, _| name.to_s.end_with?(TRANSCRIPT_SUFFIX) }.values
                            .flat_map { |log| log.each_line.filter_map { |line| transcript_event(parse_json(line)) } }
      return if transcript.empty?

      terminal_session.merge_jsonb!(:metadata, RECONCILED_KEY => Time.current.utc.iso8601)
      recorded = Array(terminal_session.reload.usage_statistic&.events_data).map { |event| call_key(event) }.tally
      missing = transcript.reject do |event|
        key = call_key(event)
        next false unless recorded[key].to_i.positive?

        recorded[key] -= 1
      end
      return if missing.empty?

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: missing, source: TRANSCRIPT_SOURCE)
    end

    # The CLI's own transcript: every user and assistant message, tool call and result
    # (1.0.108). It is the only full record of a Copilot session, because the TUI always
    # draws on the alternate screen and the terminal log keeps just its last frame.
    def session_log_paths
      super + [ "#{copilot_dir}/session-state/*/events.jsonl", MITM_LOG_PATH ]
    end

    # The model API of each seat type. Not `githubcopilot.com` whole, which adds the CLI's
    # telemetry and experiments, and not `api.github.com`: the CLI only checks the plan and
    # its own releases there, and the agent's `gh` calls to the customer's repositories go
    # to the same host.
    def mitm_tracked_domains
      %w[api.githubcopilot.com api.individual.githubcopilot.com api.business.githubcopilot.com
         api.enterprise.githubcopilot.com]
    end

    # Every transcript is named events.jsonl inside a directory named after the CLI's
    # session id, so the id goes into the stored name:
    #   session-state/<id>/events.jsonl → <id>.events.jsonl
    def session_log_name(path)
      match = %r{\A#{Regexp.escape(copilot_dir)}/session-state/([^/]+)/events\.jsonl\z}.match(path)
      match ? "#{match[1]}.events.jsonl" : super
    end

    private

    # config.json opens with `//` comment lines, which JSON.parse refuses.
    def parse_config(content)
      parse_json(content.to_s.lines.grep_v(%r{\A\s*//}).join)
    end

    def login_token(config)
      return nil unless config.is_a?(Hash)

      tokens = config["authTokens"]
      return nil unless tokens.is_a?(Hash)

      user = config["lastLoggedInUser"].is_a?(Hash) ? config["lastLoggedInUser"] : {}
      account = Array(config["loggedInUsers"]).find do |u|
        u.is_a?(Hash) && u["login"] == user["login"] && u["host"] == user["host"]
      end
      return nil if account && GITHUB_ACCOUNT_KINDS.exclude?(account["kind"])

      host = user["host"].presence || DEFAULT_HOST
      token = tokens.dig("#{host}:#{user['login']}", "token") if user["login"].present?
      return nil unless token.is_a?(String) && token.match?(TOKEN_PATTERN)

      { "token" => token, "host" => host, "login" => user["login"], "kind" => account&.dig("kind") }.compact
    end

    def token_source(token)
      case token
      when /\Agithub_pat_/ then "fine_grained_pat"
      when /\Aghu_/ then "github_app"
      else "device_flow"
      end
    end

    def gh_host(credentials)
      host = credentials.is_a?(Hash) ? credentials["host"] : nil
      URI.parse(host.presence || DEFAULT_HOST).host
    rescue URI::InvalidURIError
      nil
    end

    def mcp_type(transport)
      case transport.to_s
      when "stdio" then "local"
      when "sse" then "sse"
      else "http"
      end
    end

    def model_entry(model)
      return nil unless model.is_a?(Hash) && model["id"].present?

      { model_id: model["id"], display_name: model["name"].presence || model["id"],
        description: model["description"].to_s.truncate(120),
        reasoning_effort_levels: (model["reasoning_efforts"] if model["reasoning_efforts"].is_a?(Array)) }
    end

    def otlp_chat_events(payload, terminal_session)
      token = terminal_session.route_token
      return [] if token.blank?

      Array(payload["resourceSpans"]).flat_map do |resource_span|
        resource_attrs = resource_span.dig("resource", "attributes")
        next [] unless otlp_value(resource_attrs, "terminal_session_token") == token

        Array(resource_span["scopeSpans"]).flat_map do |scope_span|
          Array(scope_span["spans"]).filter_map { |span| chat_event(span) }
        end
      end
    end

    def chat_event(span)
      attrs = span["attributes"]
      return nil unless otlp_value(attrs, "gen_ai.operation.name") == CHAT_OPERATION

      call_event(
        model: otlp_value(attrs, "gen_ai.request.model"),
        timestamp: span["endTimeUnixNano"].presence && (span["endTimeUnixNano"].to_i / 1_000_000).to_s,
        input: otlp_value(attrs, "gen_ai.usage.input_tokens"), output: otlp_value(attrs, "gen_ai.usage.output_tokens"),
        cache_read: otlp_value(attrs, "gen_ai.usage.cache_read.input_tokens"),
        cache_write: otlp_value(attrs, "gen_ai.usage.cache_write.input_tokens"),
        nano_aiu: otlp_value(attrs, "github.copilot.nano_aiu"), source: OTEL_SOURCE
      ).merge("conversationId" => otlp_value(attrs, "gen_ai.conversation.id"), "spanId" => span["spanId"]).compact
    end

    # One `session.usage_record` line of the CLI's transcript (1.0.114).
    def transcript_event(record)
      return nil unless record.is_a?(Hash) && record["type"] == "session.usage_record"

      usage = record.dig("data", "usage")
      return nil unless usage.is_a?(Hash)

      call_event(
        model: usage["model"], timestamp: transcript_time(record["timestamp"]),
        input: usage["inputTokens"], output: usage["outputTokens"],
        cache_read: usage["cacheReadTokens"], cache_write: usage["cacheWriteTokens"],
        nano_aiu: usage.dig("copilotUsage", "totalNanoAiu"), source: TRANSCRIPT_SOURCE
      ).merge("conversationId" => usage.dig("accounting", "sourceSessionId"),
              "usageId" => usage.dig("accounting", "usageId")).compact
    end

    def call_event(model:, timestamp:, input:, output:, cache_read:, cache_write:, nano_aiu:, source:)
      cache_read = cache_read.to_i
      cache_write = cache_write.to_i
      credits = nano_aiu.to_f / NANO_AIU_PER_CREDIT
      rate = Settings.agents.copilot.ai_credit_usd.to_f

      {
        "model" => model.presence,
        "timestamp" => timestamp,
        "tokenUsage" => {
          # The CLI's input count includes the cached tokens; the platform counts them apart.
          "inputTokens" => [ input.to_i - cache_read - cache_write, 0 ].max,
          "outputTokens" => output.to_i,
          "cacheReadTokens" => cache_read,
          "cacheWriteTokens" => cache_write,
          "totalCents" => (credits * rate * 100).round(6)
        },
        "creditsUsed" => credits.round(6),
        "creditRateUsd" => rate,
        "source" => source
      }
    end

    # What a call is recognised by in either source: neither carries an id the other has.
    def call_key(event)
      usage = event["tokenUsage"].to_h
      [ event["model"], *usage.values_at("inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"),
        event["creditsUsed"] ]
    end

    def transcript_time(value)
      value.present? ? (Time.zone.parse(value.to_s).to_f * 1000).to_i.to_s : nil
    rescue ArgumentError
      nil
    end

    # OTLP/JSON carries a value as stringValue, intValue (a string), doubleValue or boolValue.
    def otlp_value(attributes, key)
      entry = Array(attributes).find { |a| a.is_a?(Hash) && a["key"] == key }
      value = entry&.dig("value")
      return nil unless value.is_a?(Hash)

      value["stringValue"] || value["intValue"] || value["doubleValue"] || value["boolValue"]
    end
  end
end
