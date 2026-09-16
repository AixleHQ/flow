# frozen_string_literal: true

require "test_helper"

module Agents
  class KiroCliAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = KiroCliAdapter.new
    end

    # Kiro keeps its login in a SQLite database, not a JSON document, and the database
    # exists from the CLI's first run. These build the three shapes measured on a real
    # container: a database the CLI merely created, one written while the device code
    # was on screen but not yet approved, and one from a finished login.
    def sqlite_blob(payload = "auth_kv page bytes")
      +"#{KiroCliAdapter::SQLITE_MAGIC}\x10\x00\x01\x01\x00\x40#{payload}"
        .force_encoding(Encoding::BINARY)
    end

    # Mid-flow: the device registration is stored as soon as the code is displayed, and
    # carries no token. Closing the terminal here must NOT persist a credential.
    def pending_sqlite_blob
      sqlite_blob("kirocli:odic:device{\"clientId\":\"x\",\"clientSecret\":\"y\"}")
    end

    # Finished: the token row's OAuth field names appear verbatim in the file's bytes.
    def authenticated_sqlite_blob(key: "kirocli:odic:token")
      sqlite_blob("#{key}{\"access_token\":\"aoa...\",\"refresh_token\":\"aor...\"}")
    end

    # A real SQLite database in the CLI's own layout, for the paths that actually read
    # it (the bearer, the profile ARN, and the API calls both feed). The byte fixtures
    # above are enough for the format checks; this is not.
    def real_state_credentials
      Tempfile.create([ "kiro-fixture", ".sqlite3" ]) do |file|
        db = SQLite3::Database.new(file.path)
        db.execute("CREATE TABLE auth_kv (key TEXT PRIMARY KEY, value TEXT)")
        db.execute("CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT)")
        db.execute("INSERT INTO auth_kv VALUES (?, ?)", [ "kirocli:odic:device-registration",
                                                          { "client_id" => "cid" }.to_json ])
        db.execute("INSERT INTO auth_kv VALUES (?, ?)", [ "kirocli:odic:token",
                                                          { "access_token" => "tok-abc",
                                                            "refresh_token" => "ref-abc" }.to_json ])
        db.execute("INSERT INTO state VALUES (?, ?)", [ Agents::KiroCliAdapter::PROFILE_STATE_KEY,
                                                        { "arn" => "arn:aws:codewhisperer:us-east-1:1234:profile/ABCD",
                                                          "profile_name" => "KiroProfile-us-east-1" }.to_json ])
        db.close

        { "state_b64" => Base64.strict_encode64(File.binread(file.path)) }
      end
    end

    # A GetUsageLimits body in the shape a live account returned, trimmed to the fields
    # that are read. The `…WithPrecision` pair is the point: the plain fields round to
    # whole credits and read 0 for anything under one.
    def stub_usage_limits(current_usage:, usage_limit: 10_000.0, overage_status: "DISABLED",
                          current_overages: 0.0, overage_cap: 10_000.0)
      body = {
        "nextDateReset" => 1_790_812_800.0,
        "overageConfiguration" => { "overageStatus" => overage_status },
        "subscriptionInfo" => { "subscriptionTitle" => "KIRO POWER" },
        "usageBreakdownList" => [ {
          "resourceType" => "CREDIT",
          "currentUsageWithPrecision" => current_usage,
          "usageLimitWithPrecision" => usage_limit,
          "currentOveragesWithPrecision" => current_overages,
          "overageCapWithPrecision" => overage_cap,
          "overageRate" => 0.04
        } ]
      }

      stub_request(:post, "https://management.us-east-1.kiro.dev/")
        .with(headers: { "X-Amz-Target" => Agents::KiroCliAdapter::USAGE_LIMITS_TARGET })
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    # A credential whose metadata already carries a credit baseline, so
    # #collect_credential_metadata does not try to seed one (which would reach the
    # vendor). Seeding is covered by its own test.
    def credential_without_metadata
      AgentCredential.new(metadata: { Agents::KiroCliAdapter::LAST_CREDITS_KEY => 1.0 })
    end

    def identity_json(sub: "kiro-user-1")
      { "sub" => sub, "email" => "dev@example.com", "license" => "pro" }.to_json
    end

    # == Paths ==

    test "home_dir and state paths follow the CLI's own layout" do
      assert_equal "/home/kiro", @adapter.home_dir
      assert_equal "/home/kiro/.local/share/kiro-cli/data.sqlite3", @adapter.state_path
    end

    test "the state database is the whole capture" do
      assert_equal [ "/home/kiro/.local/share/kiro-cli/data.sqlite3" ], @adapter.auth_file_paths
    end

    # Neither older watcher mode works here. `__present__` means "the file exists and
    # is non-empty", and the CLI creates its database on first run — before the user
    # has entered a device code — so the auth terminal would close mid-login; the
    # JSON-key mode cannot parse a binary file at all. The byte marker is what the
    # watcher watches instead, and it must be the token payload's field names rather
    # than the row key, which is named after the login method the user picked.
    test "auth completion is detected by the token marker in the database bytes" do
      assert_equal %w[__contains__:access_token __contains__:refresh_token], @adapter.auth_required_keys
    end

    test "context lands in the steering directory so /workspace stays clean" do
      assert_equal "/home/kiro/.kiro/steering/aixle-session-context.md", @adapter.context_file_path
    end

    test "skills install where the skills CLI puts them for the kiro-cli agent" do
      assert_equal "kiro-cli", @adapter.skills_agent_name
      assert_equal "/home/kiro/.kiro/skills", @adapter.skills_install_path
    end

    # == Auth completion ==

    # The database IS the credential, but only once it holds a token. Persisting one
    # without would leave the runtime looking configured while every session starts
    # signed out — the bug this gate exists to prevent.
    test "auth_complete? is true only for a database carrying a token" do
      assert @adapter.auth_complete?(authenticated_sqlite_blob)

      refute @adapter.auth_complete?(sqlite_blob)
      refute @adapter.auth_complete?(pending_sqlite_blob)
      refute @adapter.auth_complete?(identity_json)
      refute @adapter.auth_complete?("")
      refute @adapter.auth_complete?("   ")
      refute @adapter.auth_complete?("not json at all")
      refute @adapter.auth_complete?("{}")
    end

    # The row key is named after the login method, so nothing may depend on it.
    test "auth_complete? does not depend on the credential row's key name" do
      assert @adapter.auth_complete?(authenticated_sqlite_blob(key: "kirocli:odic:token"))
      assert @adapter.auth_complete?(authenticated_sqlite_blob(key: "kirocli:social:token"))
      assert @adapter.auth_complete?(authenticated_sqlite_blob(key: "kirocli:whatever:comes:next"))
    end

    # == Credential extraction ==

    test "extract_credentials stores the database as a base64 blob that round-trips" do
      blob = sqlite_blob
      credentials = @adapter.extract_credentials(blob)

      assert_equal blob, Base64.strict_decode64(credentials["state_b64"])
    end

    # Only the database is a credential. Anything else the capture hands over — a
    # stray JSON file, a leftover marker — is not turned into one.
    test "extract_credentials ignores content that is not the state database" do
      assert_equal({}, @adapter.extract_credentials(identity_json))
    end

    test "extract_credentials returns an empty hash when nothing was captured" do
      assert_equal({}, @adapter.extract_credentials(""))
      assert_equal({}, @adapter.extract_credentials("{}"))
      assert_equal({}, @adapter.extract_credentials({ "account" => nil }.to_json))
    end

    # == Config files ==

    # Straight to the path the CLI reads: every process in an agent container runs as
    # root, so there is nothing to hand over and no shell prefix on the launch command.
    test "config_files seeds the login database in place plus an MCP stub to merge into" do
      files = @adapter.config_files(@adapter.extract_credentials(sqlite_blob))

      assert_equal sqlite_blob, files["/home/kiro/.local/share/kiro-cli/data.sqlite3"]
      assert_equal({ "mcpServers" => {} }, JSON.parse(files["/home/kiro/.kiro/settings/mcp.json"]))
    end

    # `chat --trust-all-tools` opens with a blocking confirmation. Interactively that
    # is one keypress; in a non_interactive workflow step nobody can answer it and the
    # session sits at `ready` forever. The key and the file are the CLI's own — read
    # off `kiro-cli settings list --all`, and confirmed by watching cli.json change
    # after answering the prompt by hand.
    test "config_files pre-answers the trust-all confirmation the CLI opens with" do
      settings = JSON.parse(@adapter.config_files({})["/home/kiro/.kiro/settings/cli.json"])

      assert settings["chat.disableTrustAllConfirmation"]
      assert settings["app.disableAutoupdates"]
    end

    # Turning the CLI's telemetry off would take the cost figures with it: measured, a
    # container with the setting false exported nothing but a daily heartbeat, losing
    # `kiro_cli_credits_consumed`. The export is redirected, not silenced.
    test "config_files leaves the CLI's telemetry switch alone" do
      settings = JSON.parse(@adapter.config_files({})["/home/kiro/.kiro/settings/cli.json"])

      refute_includes settings.keys, "telemetry.enabled"
    end

    test "config_files omits the state file when the credential holds no login" do
      refute_includes @adapter.config_files({}).keys, "/home/kiro/.local/share/kiro-cli/data.sqlite3"
    end

    test "config_files survives a credential whose stored blob is not valid base64" do
      files = @adapter.config_files({ "state_b64" => "!!not base64!!" })

      refute_includes files.keys, "/home/kiro/.local/share/kiro-cli/data.sqlite3"
      assert_includes files.keys, "/home/kiro/.kiro/settings/mcp.json"
    end

    test "auth_setup_files seeds the shared Kiro settings before the login runs" do
      assert_includes @adapter.auth_setup_files.keys, "/home/kiro/.kiro/settings/mcp.json"
    end

    # V3 asks before anything not explicitly allowed, and nobody can answer that in a
    # non_interactive workflow step. The policy is the engine's own way of saying "the
    # container is the sandbox", rather than leaning on --trust-all-tools surviving the
    # V2→V3 transition.
    test "both containers get a permissions policy that allows every capability" do
      [ @adapter.config_files({}), @adapter.auth_setup_files ].each do |files|
        policy = YAML.safe_load(files["/home/kiro/.kiro/settings/permissions.yaml"])

        assert_equal [ { "capability" => "all", "effect" => "allow" } ], policy["rules"]
      end
    end

    # The login terminal gets the same pre-answers, so it cannot self-update mid-flow.
    test "auth_setup_files carries the CLI settings into the login terminal" do
      settings = JSON.parse(@adapter.auth_setup_files["/home/kiro/.kiro/settings/cli.json"])

      assert settings["app.disableAutoupdates"]
    end

    # == Session command ==

    # No shell prefix: the login database is seeded at its real path, so the command is
    # the CLI and nothing else. --v3 selects Kiro's current engine, which is still
    # opt-in as of CLI 2.21.0 and has to come before the subcommand.
    test "session_command launches the V3 engine with no shell plumbing around it" do
      assert_equal "kiro-cli --v3 chat --trust-all-tools", @adapter.session_command(mode: "interactive")
    end

    test "session_command shell-escapes the requested model" do
      assert_equal "kiro-cli --v3 chat --trust-all-tools --model claude-sonnet-5",
                   @adapter.session_command(mode: "interactive", model: "claude-sonnet-5")
      assert_equal "kiro-cli --v3 chat --trust-all-tools --model a\\ b\\;rm",
                   @adapter.session_command(mode: "interactive", model: "a b;rm")
    end

    # The command travels inside a single-quoted `tmux send-keys` argument
    # (AgentBaseStrategy#send_tmux_sequence), where one quote would end it early and
    # leave the CLI unlaunched.
    test "session_command contains no single quotes" do
      refute_includes @adapter.session_command(mode: "interactive"), "'"
      refute_includes @adapter.session_command(mode: "non_interactive", prompt: "go"), "'"
    end

    # The V3 TUI ignores the positional prompt AgentSessionStrategy appends, measured on
    # 2.21.3 in a real tmux pane with the trust confirmation pre-answered: it comes up
    # at an empty input and waits, so an automatic session never receives its task.
    # `--no-interactive` is the only mode that consumes the argument.
    test "session_command goes headless for an automatic session, so the prompt lands" do
      assert_equal "kiro-cli --v3 chat --trust-all-tools --no-interactive",
                   @adapter.session_command(mode: "non_interactive", prompt: "ship it")
    end

    # An interactive session carries no prompt, so it keeps the TUI.
    test "session_command keeps the TUI for an interactive session" do
      assert_equal "kiro-cli --v3 chat --trust-all-tools", @adapter.session_command(mode: "interactive")
    end

    # == MCP ==

    test "mcp_config writes stdio and remote servers into the user-scope mcp.json" do
      stdio = OpenStruct.new(name: "Local Tools", transport: "stdio", command: "npx",
                             args: [ "-y", "server" ], env_vars: { "TOKEN" => "t" }, url: nil, headers: nil)
      remote = OpenStruct.new(name: "Aixle Tools", transport: "http", command: nil, args: nil,
                              url: "https://example.test/mcp", headers: { "Authorization" => "Bearer x" })

      files = @adapter.mcp_config([ stdio, remote ])
      servers = JSON.parse(files["/home/kiro/.kiro/settings/mcp.json"])["mcpServers"]

      local = servers[MCPServer.config_key_for("Local Tools")]
      assert_equal "npx", local["command"]
      assert_equal [ "-y", "server" ], local["args"]
      refute local["disabled"]

      hosted = servers[MCPServer.config_key_for("Aixle Tools")]
      assert_equal "https://example.test/mcp", hosted["url"]
      assert_equal({ "Authorization" => "Bearer x" }, hosted["headers"])
      # Kiro infers the transport from which of url/command is present — a type field
      # would be a field the CLI does not read.
      refute hosted.key?("type")
    end

    # Kiro's V3 agent refuses a plain-HTTP MCP server whose host is not loopback, and
    # refuses it SILENTLY — the server just never appears among the agent's tools, which
    # is how a session ends up unable to call finish_session. Measured against 2.21.3:
    # `http://web:4002` yielded "Power 'aixle-tools' is not installed", the same server
    # on `http://localhost:4002` yielded mcp_aixle_tools_finish_session. The CLI's own
    # message is "host must be 127.0.0.1 or localhost, got `web`".
    test "mcp_config points an internal HTTP server at the container's loopback forward" do
      internal = OpenStruct.new(name: "Aixle Tools", transport: "http", command: nil, args: nil,
                                url: "http://web:4002/action_mcp", headers: { "X-Session-Key" => "k" })

      servers = JSON.parse(@adapter.mcp_config([ internal ])["/home/kiro/.kiro/settings/mcp.json"])["mcpServers"]
      entry = servers[MCPServer.config_key_for("Aixle Tools")]

      assert_equal "http://localhost:4002/action_mcp", entry["url"]
      # The path and headers are the session's credential — only the host may move.
      assert_equal({ "X-Session-Key" => "k" }, entry["headers"])
    end

    # An HTTPS server needs no forwarding, and a URL that is already loopback must not be
    # rewritten onto a different port.
    test "mcp_config leaves servers Kiro already accepts alone" do
      [ "https://mcp.example.test/action_mcp", "http://localhost:9999/action_mcp" ].each do |url|
        server = OpenStruct.new(name: "Remote", transport: "http", command: nil, args: nil, url: url, headers: nil)
        servers = JSON.parse(@adapter.mcp_config([ server ])["/home/kiro/.kiro/settings/mcp.json"])["mcpServers"]

        assert_equal url, servers[MCPServer.config_key_for("Remote")]["url"]
      end
    end

    # The forward is what makes the loopback URL resolve, so the container is told where
    # to send it. Every deployment of this platform serves MCP over internal HTTP.
    test "default_env_vars asks the container to forward the platform's MCP service" do
      session = build(:terminal_session, agent_type: "kiro_cli", route_token: "tok-1")

      env = @adapter.default_env_vars(session)

      assert_equal "4002", env["MCP_FORWARD_PORT"]
      assert_equal URI.parse(Settings.mcp.server_url).then { |u| "#{u.host}:#{u.port}" }, env["MCP_FORWARD_TARGET"]
    end

    test "mcp config merges into the shared IDE/CLI document rather than replacing it" do
      assert_equal :merge_json, @adapter.mcp_merge_strategy
      assert_equal "/home/kiro/.kiro/settings/mcp.json", @adapter.mcp_config_path
    end

    # == Environment ==

    # A KIRO_API_KEY left in the environment is a credential for a different account,
    # and this runtime never holds one — every login here is the device-code flow.
    test "conflicting_env_keys always drops a stray API key" do
      assert_equal %w[KIRO_API_KEY], @adapter.conflicting_env_keys({})
      assert_equal %w[KIRO_API_KEY], @adapter.conflicting_env_keys({ "state_b64" => "x" })
    end

    # Kiro meters in credits and publishes no per-request token counts outside headless
    # mode, so there is deliberately no expiry to derive and no usage to collect.
    test "the credential carries no derivable expiry" do
      assert_nil @adapter.token_expires_at(@adapter.extract_credentials(sqlite_blob))
    end

    test "kiro_cli is not in the refreshable set — there is no refresh endpoint" do
      refute_includes AgentCredential::REFRESHABLE_AGENT_TYPES, "kiro_cli"
    end

    # == Telemetry (the primary cost source) ==

    # The CLI's OTLP export goes wherever it is pointed, so it is pointed here — and
    # `OTEL_RESOURCE_ATTRIBUTES` is what lets UsageStatisticsService route a batch back
    # to the session that produced it (honoured by the CLI's SDK, verified on 2.21.3).
    test "default_env_vars redirects the CLI's telemetry at the platform collector" do
      session = build(:terminal_session, agent_type: "kiro_cli", route_token: "tok-123")

      env = @adapter.default_env_vars(session)

      assert_equal "1", env["KIRO_TELEMETRY_OTEL"]
      assert_equal Settings.otel.endpoint, env["KIRO_TELEMETRY_OTLP_ENDPOINT"]
      assert_equal "terminal_session_token=tok-123", env["OTEL_RESOURCE_ATTRIBUTES"]
      # Measured: this one stops the export altogether, cost figures included.
      refute_includes env.keys, "KIRO_DISABLE_TELEMETRY"
    end

    # One OTLP batch in the exact shape the platform's collector forwards, taken from a
    # live session: a DELTA sum, credits in `asDouble`, `terminal_session_token` on the
    # resource and `model`/`session_id` on the data point.
    def otlp_credits_payload(token:, credits: 0.045368, model: "claude-opus-5",
                             temporality: "AGGREGATION_TEMPORALITY_DELTA")
      {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [
            { "key" => "service.name", "value" => { "stringValue" => "kiro-cli" } },
            { "key" => "terminal_session_token", "value" => { "stringValue" => token } }
          ] },
          "scopeMetrics" => [ { "metrics" => [ {
            "name" => Agents::KiroCliAdapter::CREDITS_METRIC,
            "sum" => {
              "aggregationTemporality" => temporality,
              "isMonotonic" => true,
              "dataPoints" => [ {
                "attributes" => [
                  { "key" => "model", "value" => { "stringValue" => model } },
                  { "key" => "session_id", "value" => { "stringValue" => "sess_abc" } },
                  { "key" => "request_id", "value" => { "stringValue" => "req_1" } }
                ],
                "timeUnixNano" => "1789155921186145148",
                "asDouble" => credits
              } ]
            }
          } ] } ]
        } ]
      }
    end

    def kiro_session_with_credential(rate: 0.04, token: "tok-otel")
      company = create(:company)
      user = create(:user, company: company)
      create(:agent_credential, user: user, company: company, agent_type: "kiro_cli",
                                metadata: { Agents::KiroCliAdapter::CREDIT_RATE_KEY => rate })
      create(:terminal_session, user: user, agent_type: "kiro_cli", route_token: token)
    end

    test "ingest_usage prices a telemetry batch and attributes it to the session" do
      session = kiro_session_with_credential

      assert_equal :ok, @adapter.ingest_usage(otlp_credits_payload(token: "tok-otel"), session)

      stat = session.reload.usage_statistic
      assert_equal [ "claude-opus-5" ], stat.models
      assert_in_delta 0.1814, stat.total_cents_precise.to_f, 0.001
      assert_equal 0, stat.input_tokens
      event = stat.events_data.sole
      assert_in_delta 0.045368, event["creditsUsed"]
      assert_equal "otlp_credits_consumed", event["source"]
    end

    # DELTA batches are new spend, so two of them add up rather than replacing.
    test "ingest_usage accumulates successive telemetry batches" do
      session = kiro_session_with_credential

      @adapter.ingest_usage(otlp_credits_payload(token: "tok-otel", credits: 0.1), session)
      @adapter.ingest_usage(otlp_credits_payload(token: "tok-otel", credits: 0.2), session)

      assert_in_delta 1.2, session.reload.usage_statistic.total_cents_precise.to_f, 0.001
    end

    # A cumulative sum restates the total each time. Adding those up would multiply the
    # bill, so an unfamiliar temporality is ignored rather than guessed at.
    test "ingest_usage ignores a sum that is not delta temporality" do
      session = kiro_session_with_credential
      payload = otlp_credits_payload(token: "tok-otel", temporality: "AGGREGATION_TEMPORALITY_CUMULATIVE")

      assert_equal :accepted, @adapter.ingest_usage(payload, session)
      assert_nil session.reload.usage_statistic
    end

    # Batches are routed by resource attribute; another session's must not land here.
    test "ingest_usage ignores a batch belonging to another session" do
      session = kiro_session_with_credential

      assert_equal :accepted, @adapter.ingest_usage(otlp_credits_payload(token: "someone-else"), session)
      assert_nil session.reload.usage_statistic
    end

    # "unknown" is what the CLI sends when the turn ran on the account default, and it
    # is not a model name anyone should see in the UI.
    test "ingest_usage drops the placeholder model the CLI sends for a default run" do
      session = kiro_session_with_credential

      @adapter.ingest_usage(otlp_credits_payload(token: "tok-otel", model: "unknown"), session)

      assert_empty session.reload.usage_statistic.models
    end

    # == Model catalogue ==

    # Asking the CLI is the only reliable route: which service serves the catalogue
    # depends on the engine the account is on, and on a v3 account CodeWhisperer's
    # ListAvailableModels answers 403 while the CLI returns a fuller list.
    test "collect_credential_metadata asks the CLI for the catalogue" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "kiro_cli")
      container = runtime.resolve_container("abc123")

      extras = @adapter.collect_credential_metadata(runtime, container, credential_without_metadata, :session)

      assert_equal %w[kiro_models], extras.keys
      assert_equal %w[auto claude-opus-5 qwen3-coder-next], extras["kiro_models"].map { |m| m["model_id"] }
      assert_includes runtime.execs.map { |cmd| Array(cmd).join(" ") }, "kiro-cli --v3 chat --list-models --format json"
    end

    test "collect_credential_metadata writes nothing when the CLI cannot answer" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "kiro_cli")
      runtime.fail_exec("--list-models", stderr: "not logged in", exit_code: 1)

      assert_empty @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential_without_metadata, :session)
    end

    # The picker reads what the CLI reported, in the CLI's own snake_case.
    test "fetch_available_models prefers the captured catalogue" do
      credential = AgentCredential.new(metadata: { "kiro_models" => [
        { "model_id" => "claude-opus-5", "model_name" => "claude-opus-5", "description" => "Claude Opus 5",
          "context_window_tokens" => 1_000_000, "rate_multiplier" => 2.2, "rate_unit" => "Credit" }
      ] })

      models = @adapter.fetch_available_models({}, credential: credential)

      assert_equal 1, models.size
      assert_equal "claude-opus-5", models.first[:model_id]
      assert_equal "2.2x credits · 1000000 input tokens · Claude Opus 5", models.first[:description]
    end

    # Fallback for a credential captured before the CLI was ever asked. The API answers
    # camelCase and nests the context window, so the same entry arrives in a different
    # shape than the CLI's.
    test "fetch_available_models falls back to the API, reading its camelCase shape" do
      stub_request(:post, "https://management.us-east-1.kiro.dev/")
        .with(headers: { "X-Amz-Target" => Agents::KiroCliAdapter::LIST_MODELS_TARGET })
        .to_return(status: 200, body: { "models" => [
          { "modelId" => "claude-sonnet-4.5", "modelName" => "claude-sonnet-4.5", "description" => "Sonnet 4.5",
            "rateMultiplier" => 1.3, "rateUnit" => "Credit", "tokenLimits" => { "maxInputTokens" => 200_000 } }
        ] }.to_json, headers: { "Content-Type" => "application/json" })

      models = @adapter.fetch_available_models(real_state_credentials, credential: nil)

      assert_equal 1, models.size
      assert_equal "claude-sonnet-4.5", models.first[:model_id]
      assert_equal "1.3x credits · 200000 input tokens · Sonnet 4.5", models.first[:description]
    end

    # Cost is a delta, so without a baseline the very first session reports nothing.
    # The baseline is seeded once, at login, from the auth container.
    test "collect_credential_metadata seeds the credit baseline for a new credential" do
      stub_usage_limits(current_usage: 12.5)
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "kiro_cli")
      credential = AgentCredential.new(config_data: real_state_credentials, metadata: {})

      extras = @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential, :auth)

      assert_in_delta 12.5, extras[Agents::KiroCliAdapter::LAST_CREDITS_KEY]
    end

    # #collect_usage owns the key after login, and this hook runs BEFORE it during
    # session cleanup — seeding there would make that very session measure zero.
    test "collect_credential_metadata seeds no baseline at the end of a session" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "kiro_cli")
      credential = AgentCredential.new(config_data: real_state_credentials, metadata: {})

      extras = @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential, :session)

      assert_equal %w[kiro_models], extras.keys
    end

    test "collect_credential_metadata never overwrites an existing credit baseline" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "kiro_cli")
      credential = AgentCredential.new(config_data: real_state_credentials,
                                       metadata: { Agents::KiroCliAdapter::LAST_CREDITS_KEY => 3.0 })

      extras = @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential, :auth)

      refute extras.key?(Agents::KiroCliAdapter::LAST_CREDITS_KEY)
    end

    # == Subscription usage (the profile card) ==

    # Kiro has no rolling windows like Claude's five-hour bucket — one credit allowance
    # per billing period — and a plan measured in credits is only useful with the counts
    # alongside the percentage.
    test "fetch_subscription_usage reports the credit allowance with its raw counts" do
      stub_usage_limits(current_usage: 2500.0, usage_limit: 10_000.0)

      usage = @adapter.fetch_subscription_usage(real_state_credentials)

      assert_equal "ok", usage[:status]
      window = usage[:windows].sole
      assert_equal "kiro_credits", window[:key]
      assert_in_delta 25.0, window[:utilization]
      assert_in_delta 2500.0, window[:used]
      assert_in_delta 10_000.0, window[:limit]
      assert_equal "credits", window[:unit]
      assert_equal "KIRO POWER", window[:plan]
    end

    # An account with pay-as-you-go switched off still reports a cap. Showing it would
    # read as headroom the user does not have.
    test "fetch_subscription_usage omits overage while it is disabled" do
      stub_usage_limits(current_usage: 1.0, overage_status: "DISABLED")

      assert_nil @adapter.fetch_subscription_usage(real_state_credentials)[:extra_usage]
    end

    test "fetch_subscription_usage reports overage once the account enables it" do
      stub_usage_limits(current_usage: 1.0, overage_status: "ENABLED", current_overages: 40.0, overage_cap: 200.0)

      extra = @adapter.fetch_subscription_usage(real_state_credentials)[:extra_usage]

      assert extra[:enabled]
      assert_in_delta 20.0, extra[:utilization]
      assert_in_delta 40.0, extra[:used_credits]
      assert_in_delta 200.0, extra[:monthly_limit]
    end

    # The two halves of the credential live in two tables: the token in `auth_kv`, the
    # profile ARN — which every call must carry, and which names the region they go to —
    # in `state`. Reading only the token yields a record the API rejects.
    test "the bearer and the profile ARN are read from their separate tables" do
      record = @adapter.send(:auth_record, Base64.strict_decode64(real_state_credentials["state_b64"]))

      assert_equal "tok-abc", record["access_token"]
      assert_equal "arn:aws:codewhisperer:us-east-1:1234:profile/ABCD", record["profile_arn"]
    end
  end
end
