# frozen_string_literal: true

require "test_helper"

module Agents
  class CodexAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = CodexAdapter.new
    end

    test "config_path returns codex auth.json path" do
      assert_equal "/home/codex/.codex/auth.json", @adapter.config_path
    end

    test "home_dir returns codex home" do
      assert_equal "/home/codex", @adapter.home_dir
    end

    test "auth_required_keys returns tokens" do
      assert_equal %w[tokens], @adapter.auth_required_keys
    end

    test "auth_complete? returns true with access_token" do
      content = { "tokens" => { "access_token" => "abc123" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns true with refresh_token" do
      content = { "tokens" => { "refresh_token" => "refresh123" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false without tokens" do
      content = {}.to_json
      refute @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false when tokens is not a hash" do
      content = { "tokens" => "invalid" }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "extract_credentials extracts relevant fields" do
      content = {
        "tokens" => { "access_token" => "abc" },
        "OPENAI_API_KEY" => "sk-123",
        "account_id" => "acc-456",
        "last_refresh" => "2024-01-01",
        "other_field" => "ignored"
      }.to_json

      credentials = @adapter.extract_credentials(content)

      assert_equal({ "access_token" => "abc" }, credentials["tokens"])
      assert_equal "sk-123", credentials["OPENAI_API_KEY"]
      assert_equal "acc-456", credentials["account_id"]
      assert_equal "2024-01-01", credentials["last_refresh"]
      refute credentials.key?("other_field")
    end

    test "generate_config returns credentials with last_refresh" do
      credentials = { "tokens" => { "access_token" => "abc" } }

      config = @adapter.generate_config(credentials)

      assert_equal({ "access_token" => "abc" }, config["tokens"])
      assert config["last_refresh"].present?
    end

    test "generate_config preserves existing last_refresh" do
      credentials = { "last_refresh" => "2024-01-01" }

      config = @adapter.generate_config(credentials)

      assert_equal "2024-01-01", config["last_refresh"]
    end

    test "config_files returns auth.json and config.toml" do
      credentials = { "tokens" => { "access_token" => "abc" } }
      stub_codex_models([])

      files = @adapter.config_files(credentials, { workspace: "/project" })

      assert files.key?("/home/codex/.codex/auth.json")
      assert files.key?("/home/codex/.codex/config.toml")

      # Check auth.json content
      auth = JSON.parse(files["/home/codex/.codex/auth.json"])
      assert_equal({ "access_token" => "abc" }, auth["tokens"])

      # Check config.toml content (no model line when model not specified)
      toml = files["/home/codex/.codex/config.toml"]
      assert_includes toml, 'approval_policy = "never"'
      assert_includes toml, 'sandbox_mode = "danger-full-access"'
      assert_includes toml, 'trust_level = "trusted"'
      assert_includes toml, "/project"
    end

    test "config_files uses default workspace when not provided" do
      credentials = {}
      files = @adapter.config_files(credentials)

      toml = files["/home/codex/.codex/config.toml"]
      assert_includes toml, "/workspace"
    end

    # =========================================================================
    # Startup model-migration dialog suppression (task #534)
    #
    # Codex CLI blocks the session on the "try the new model" dialog unless
    # notice.model_migrations[<model it is about to run>] already points at the
    # exact upgrade target the model catalog advertises. The model it runs is the
    # session model when one is configured and the catalog default otherwise.
    # =========================================================================

    test "config_files acknowledges the migration target the catalog advertises" do
      stub_codex_models([
        { "slug" => "gpt-5.6-terra", "visibility" => "list" },
        { "slug" => "gpt-5.4", "visibility" => "hide", "upgrade" => { "model" => "gpt-5.6-terra" } }
      ])

      toml = codex_toml({ model: "gpt-5.4" })

      assert_includes toml, "[notice.model_migrations]"
      assert_includes toml, '"gpt-5.4" = "gpt-5.6-terra"'
    end

    test "config_files acknowledges migrations for models the session did not pin" do
      # Without a configured model Codex runs the catalog default, so acknowledging
      # only the configured model leaves the dialog armed for every other model.
      stub_codex_models([
        { "slug" => "gpt-5.4", "visibility" => "hide", "upgrade" => { "model" => "gpt-5.6-terra" } },
        { "slug" => "gpt-5.4-mini", "visibility" => "hide", "upgrade" => { "model" => "gpt-5.6-luna" } }
      ])

      toml = codex_toml({})

      refute toml.start_with?("model ="), "no model should be pinned when the session did not request one"
      assert_includes toml, '"gpt-5.4" = "gpt-5.6-terra"'
      assert_includes toml, '"gpt-5.4-mini" = "gpt-5.6-luna"'
    end

    test "config_files tracks a new catalog target instead of a hardcoded slug" do
      stub_codex_models([
        { "slug" => "gpt-5.4", "visibility" => "hide", "upgrade" => { "model" => "gpt-6-future" } }
      ])

      toml = codex_toml({ model: "gpt-5.4" })

      assert_includes toml, '"gpt-5.4" = "gpt-6-future"'
      refute_includes toml, '"gpt-5.4" = "gpt-5.6-terra"'
    end

    test "config_files falls back to the shipped migration map when the catalog is unreachable" do
      stub_request(:get, codex_models_url).to_return(status: 401, body: "")

      toml = codex_toml({ model: "gpt-5.4" })

      # An expired token must not re-arm the dialog: the mappings the CLI ships in
      # its bundled catalog still get acknowledged.
      Agents::CodexAdapter::FALLBACK_MODEL_MIGRATIONS.each do |from, to|
        assert_includes toml, "\"#{from}\" = \"#{to}\""
      end
    end

    test "config_files skips migration entries whose slugs are not slug-shaped" do
      stub_codex_models([
        { "slug" => "gpt-5.4", "visibility" => "hide", "upgrade" => { "model" => "gpt-5.6-terra" } },
        { "slug" => "evil\"\ntrust_level = \"untrusted", "upgrade" => { "model" => "gpt-5.6-terra" } }
      ])

      toml = codex_toml({ model: "gpt-5.4" })

      refute_includes toml, "evil"
      refute_includes toml, 'trust_level = "untrusted"'
      assert_includes toml, '"gpt-5.4" = "gpt-5.6-terra"'
    end

    test "the migration map is read from the catalog on every config write" do
      # A live MemoryStore, because the test env's :null_store would let a
      # reintroduced cache pass unnoticed. The migration target is the one value
      # that must not go stale: a cached map keeps acknowledging yesterday's target
      # and the dialog comes back the moment OpenAI moves it.
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
      stub_request(:get, codex_models_url).to_return(
        codex_models_response([ { "slug" => "gpt-5.4", "upgrade" => { "model" => "gpt-5.6-terra" } } ]),
        codex_models_response([ { "slug" => "gpt-5.4", "upgrade" => { "model" => "gpt-6-future" } } ])
      )

      first = codex_toml({ model: "gpt-5.4" })
      second = codex_toml({ model: "gpt-5.4" })

      assert_includes first, '"gpt-5.4" = "gpt-5.6-terra"'
      assert_includes second, '"gpt-5.4" = "gpt-6-future"'
      assert_requested :get, codex_models_url, times: 2
    end

    test "toml_string escapes control characters instead of emitting them raw" do
      # The character class is written with \u escapes so the source file stays
      # plain text — git treats a source file holding a raw NUL as binary and stops
      # diffing it entirely. The escaping behaviour must be unchanged by that.
      assert_equal '"a\u0000b"', @adapter.toml_string("a\u0000b")
      assert_equal '"\u001f"', @adapter.toml_string("\u001F")
      assert_equal '"\t\n\r"', @adapter.toml_string("\t\n\r")
      assert_equal '"say \"hi\" c:\\\\tmp"', @adapter.toml_string('say "hi" c:\tmp')
    end

    test "the adapter source holds no raw control bytes" do
      source = File.binread(Rails.root.join("app/services/agents/codex_adapter.rb"))

      offenders = source.bytes.uniq.select { |b| b < 0x20 && ![ 0x09, 0x0a, 0x0d ].include?(b) }

      assert_empty offenders.map { |b| format("0x%02x", b) },
                   "control bytes in the source make git diff the whole file as binary"
    end

    test "config_files pre-acknowledges the remaining Codex startup notices" do
      stub_codex_models([])

      toml = codex_toml({})

      assert_includes toml, "hide_full_access_warning = true"
      assert_includes toml, "hide_rate_limit_model_nudge = true"
      assert_includes toml, "hide_gpt5_1_migration_prompt = true"
      assert_includes toml, '"hide_gpt-5.1-codex-max_migration_prompt" = true'
      # The trust dialog stays suppressed through the project entry.
      assert_includes toml, 'trust_level = "trusted"'
    end

    test "fetch_subscription_usage returns nil for an API-key login" do
      assert_nil @adapter.fetch_subscription_usage({ "OPENAI_API_KEY" => "sk-test" })
    end

    test "fetch_subscription_usage maps upstream windows, reset periods, and credit units" do
      Codex::Api.expects(:usage).with(access_token: "tok", account_id: "acct-1").returns({
        "rate_limit" => {
          "primary_window" => { "used_percent" => 42, "limit_window_seconds" => 18_000, "reset_at" => 1_725_000_000 },
          "secondary_window" => { "used_percent" => 5, "limit_window_seconds" => 604_800, "reset_at" => 1_725_600_000 }
        },
        "spend_control" => {
          "individual_limit" => { "limit" => "25000", "used" => "8000", "used_percent" => 32 }
        }
      })

      usage = @adapter.fetch_subscription_usage({
        "tokens" => { "access_token" => "tok", "account_id" => "acct-1" }
      })

      assert_equal "ok", usage[:status]
      assert_equal %w[codex_primary codex_secondary], usage[:windows].pluck(:key)
      assert_equal [ 300.0, 10_080.0 ], usage[:windows].pluck(:window_duration_mins)
      assert_equal "2024-08-30T06:40:00Z", usage[:windows].first[:resets_at]
      assert_equal({ enabled: true, utilization: 32.0, monthly_limit: 25_000, used_credits: 8_000 }, usage[:extra_usage])
    end

    test "fetch_subscription_usage accepts the legacy top-level account id" do
      Codex::Api.expects(:usage).with(access_token: "tok", account_id: "legacy-acct").returns({})

      usage = @adapter.fetch_subscription_usage({
        "tokens" => { "access_token" => "tok" }, "account_id" => "legacy-acct"
      })

      assert_equal "ok", usage[:status]
    end

    test "fetch_subscription_usage exposes authentication, throttling, and transport states" do
      credentials = { "tokens" => { "access_token" => "tok" } }

      Codex::Api.stubs(:usage).raises(Codex::Api::UnauthorizedError.new("unauthorized", status: 401))
      assert_equal({ status: "unauthorized" }, @adapter.fetch_subscription_usage(credentials))

      Codex::Api.stubs(:usage).raises(Codex::Api::HTTPError.new("slow", status: 429))
      assert_equal({ status: "rate_limited" }, @adapter.fetch_subscription_usage(credentials))

      Codex::Api.stubs(:usage).raises(Codex::Api::TimeoutError, "timeout")
      assert_equal({ status: "unavailable" }, @adapter.fetch_subscription_usage(credentials))
    end

    test "auth_setup_files writes config.toml without calling the models API" do
      # Auth has not happened yet, so there is no token to fetch the catalog with —
      # the pre-auth config must still be written (and must not raise).
      toml = @adapter.auth_setup_files["/home/codex/.codex/config.toml"]

      assert_includes toml, 'cli_auth_credentials_store = "file"'
      assert_includes toml, "[notice.model_migrations]"
    end

    test "models are requested with a client version new enough for the current catalog" do
      # The endpoint hides models whose minimal_client_version is above the version
      # we claim — the gpt-5.6 family requires 0.144.0, which is why an older
      # client_version left those models out of the model picker entirely.
      assert_operator Gem::Version.new(Codex::Api::CLIENT_VERSION),
                      :>=, Gem::Version.new("0.144.0"),
                      "Codex::Api::CLIENT_VERSION must be at least the gpt-5.6 minimal client version"

      request = stub_codex_models([
        { "slug" => "gpt-5.6-sol", "display_name" => "GPT-5.6-Sol", "description" => "Fast", "visibility" => "list" },
        { "slug" => "gpt-5.4", "display_name" => "GPT-5.4", "visibility" => "hide" }
      ])

      models = @adapter.fetch_available_models({ "tokens" => { "access_token" => "tok" } })

      assert_requested request
      assert_equal [ "gpt-5.6-sol" ], models.map { |m| m[:model_id] }
    end

    test "fetch_available_models refreshes a rejected access token and retries once" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :codex, user: user, config_data: {
        "tokens" => { "access_token" => "stale", "refresh_token" => "r1" }
      })
      stub_request(:get, codex_models_url)
        .with(headers: { "Authorization" => "Bearer stale" })
        .to_return(status: 401, body: "")
      stub_request(:post, Codex::Api::OAUTH_TOKEN_URL)
        .to_return(status: 200, body: { access_token: "fresh" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      retried = stub_request(:get, codex_models_url)
        .with(headers: { "Authorization" => "Bearer fresh" })
        .to_return(codex_models_response([ { "slug" => "gpt-5.6-sol", "visibility" => "list" } ]))

      models = @adapter.fetch_available_models(credential.config_data, credential: credential)

      assert_requested retried
      assert_equal [ "gpt-5.6-sol" ], models.map { |m| m[:model_id] }
      assert_equal "fresh", credential.reload.config_data.dig("tokens", "access_token")
    end

    test "fetch_available_models returns nothing when the token is rejected and cannot be refreshed" do
      stub_request(:get, codex_models_url).to_return(status: 401, body: "")

      assert_empty @adapter.fetch_available_models({ "tokens" => { "access_token" => "stale" } })
    end

    # The reviewer's layering ask (PR #92): the vendor transport belongs in
    # Codex::Api, and the adapter is only allowed to call it. A raw HTTP call
    # sneaking back in here is the regression this guards.
    test "the adapter speaks to the Codex API only through Codex::Api" do
      source = File.read(Rails.root.join("app/services/agents/codex_adapter.rb"))

      assert_no_match(/Net::HTTP|Faraday|URI\(/, source,
                      "HTTP transport belongs in Codex::Api, not in the adapter")
      assert_no_match(%r{https://(chatgpt\.com|auth\.openai\.com)}, source,
                      "vendor endpoints belong in Codex::Api, not in the adapter")
    end

    test "session_command returns codex --yolo for any mode" do
      expected = "codex --yolo -c projects./workspace.trust_level=trusted"

      assert_equal expected, @adapter.session_command(mode: "interactive")
      assert_equal expected, @adapter.session_command(mode: "non_interactive", prompt: "Run tests")
    end

    test "session_command includes model flag when model provided" do
      result = @adapter.session_command(mode: "interactive", model: "gpt-5.3-codex")

      assert_equal "codex --model gpt-5.3-codex --yolo -c projects./workspace.trust_level=trusted", result
    end

    # =========================================================================
    # Workspace-trust prompt (task #605)
    #
    # `--yolo` does NOT cover Codex's "Do you trust the contents of this directory?"
    # dialog — it is keyed on the cwd, not on a notice flag. A non_interactive
    # workflow step that reaches it produces no further output and never finishes,
    # so trust is granted twice: in config.toml AND on the launch command, because
    # config.toml is read-modify-written after it is created and can lose the entry.
    # =========================================================================

    test "session_command grants workspace trust so the launch cannot depend on config.toml" do
      assert_includes @adapter.session_command(mode: "non_interactive", prompt: "Run tests"),
                      "-c projects./workspace.trust_level=trusted"
    end

    test "the trust flag survives the shell quoting the launch path applies to it" do
      # Keep the flag simple even though AgentBaseStrategy#send_tmux_sequence now
      # shell-escapes complete commands before passing them to tmux.
      flag = @adapter.cli_trust_flag.strip

      assert_equal flag, Shellwords.split(flag).join(" ")
      assert_no_match(/['"\\$`]/, flag)
    end

    test "cli_trust_flag is dropped for a workspace it cannot address" do
      # Codex splits a -c path on ".", and the quoting above rules out spaces, so a
      # path like these can only be trusted through config.toml.
      assert_equal "", @adapter.cli_trust_flag("/work.space")
      assert_equal "", @adapter.cli_trust_flag("/work space")
      assert_equal "", @adapter.cli_trust_flag("")
    end

    test "cli_trust_flag trusts exactly the workspace config.toml trusts" do
      stub_codex_models([])

      toml = codex_toml({ workspace: "/srv/agent" })

      assert_includes toml, '[projects."/srv/agent"]'
      assert_includes @adapter.cli_trust_flag("/srv/agent"), "projects./srv/agent.trust_level=trusted"
    end

    # =========================================================================
    # collect_usage — OTLP metrics extraction
    # =========================================================================

    test "collect_usage extracts tokens from OTLP metrics in MITM log" do
      session = create_terminal_session(agent_type: "codex")
      mitm_log = build_otlp_mitm_log(
        token_data: { "input" => 1000, "output" => 200, "cached_input" => 800, "reasoning_output" => 50 },
        model: "gpt-5.1-codex-mini"
      )

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert stat, "UsageStatistic should be created"
      assert_equal 1000, stat.input_tokens
      assert_equal 200, stat.output_tokens
      assert_equal 800, stat.cache_read_tokens
      assert_equal "otlp_metrics", stat.source
      assert_equal [ "gpt-5.1-codex-mini" ], stat.models
    end

    test "collect_usage sums delta OTLP batches" do
      session = create_terminal_session(agent_type: "codex")
      batch1 = build_otlp_metrics_json(
        token_data: { "input" => 500, "output" => 100 }, model: "gpt-5.1-codex-mini"
      )
      batch2 = build_otlp_metrics_json(
        token_data: { "input" => 700, "output" => 300 }, model: "gpt-5.1-codex-mini"
      )
      mitm_log = [
        mitm_request_line("/otlp/v1/metrics", batch1),
        mitm_response_line("/otlp/v1/metrics", 202),
        mitm_request_line("/otlp/v1/metrics", batch2),
        mitm_response_line("/otlp/v1/metrics", 202)
      ].join("\n") + "\n"

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert_equal 1200, stat.input_tokens
      assert_equal 400, stat.output_tokens
    end

    test "collect_usage falls back to legacy HTTP parsing when no OTLP data" do
      session = create_terminal_session(agent_type: "codex")
      response_body = '{"model":"gpt-4o","usage":{"input_tokens":500,"output_tokens":100,"total_tokens":600}}'
      mitm_log = [
        mitm_response_line("/backend-api/codex/responses", 200, response_body)
      ].join("\n") + "\n"

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert stat, "UsageStatistic should be created via legacy path"
      assert_equal 500, stat.input_tokens
      assert_equal 100, stat.output_tokens
      assert_equal "mitm", stat.source
    end

    test "collect_usage handles empty MITM log gracefully" do
      session = create_terminal_session(agent_type: "codex")
      @adapter.collect_usage(session, { "logs/http.log" => "" })
      assert_nil session.reload.usage_statistic
    end

    test "collect_usage handles missing MITM log gracefully" do
      session = create_terminal_session(agent_type: "codex")
      @adapter.collect_usage(session, {})
      assert_nil session.reload.usage_statistic
    end

    test "collect_usage skips when OTLP ingest already populated usage" do
      session = create_terminal_session(agent_type: "codex")
      session.create_usage_statistic!(
        input_tokens: 500, output_tokens: 100, source: "otlp",
        events_count: 1, events_data: [], cost_cents: 0
      )

      mitm_log = build_otlp_mitm_log(
        token_data: { "input" => 9999, "output" => 9999 },
        model: "gpt-5.1-codex-mini"
      )

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert_equal 500, stat.input_tokens, "Should not overwrite existing OTLP usage"
    end

    # =========================================================================
    # ingest_usage — real-time OTLP log processing
    # =========================================================================

    test "ingest_usage creates usage from OTLP log events" do
      session = create_terminal_session(agent_type: "codex")
      payload = build_otlp_log_payload(
        token: session.route_token,
        input_tokens: 1000, output_tokens: 200,
        cached_tokens: 800, reasoning_tokens: 50,
        model: "gpt-5.1-codex-mini"
      )

      result = @adapter.ingest_usage(payload, session)

      assert_equal :ok, result
      stat = session.reload.usage_statistic
      assert stat, "UsageStatistic should be created"
      assert_equal 1000, stat.input_tokens
      assert_equal 200, stat.output_tokens
      assert_equal 800, stat.cache_read_tokens
      assert_equal "otlp", stat.source
      assert_equal [ "gpt-5.1-codex-mini" ], stat.models
    end

    test "ingest_usage accumulates across multiple batches" do
      session = create_terminal_session(agent_type: "codex")
      payload1 = build_otlp_log_payload(
        token: session.route_token,
        input_tokens: 500, output_tokens: 100, model: "gpt-5.1-codex-mini"
      )
      payload2 = build_otlp_log_payload(
        token: session.route_token,
        input_tokens: 700, output_tokens: 300, model: "gpt-5.1-codex-mini"
      )

      @adapter.ingest_usage(payload1, session)
      @adapter.ingest_usage(payload2, session)

      stat = session.reload.usage_statistic
      assert_equal 1200, stat.input_tokens
      assert_equal 400, stat.output_tokens
      assert_equal 2, stat.events_count
    end

    test "ingest_usage returns accepted when no matching events" do
      session = create_terminal_session(agent_type: "codex")
      payload = { "resourceLogs" => [] }

      result = @adapter.ingest_usage(payload, session)
      assert_equal :accepted, result
      assert_nil session.reload.usage_statistic
    end

    test "ingest_usage ignores events for different session tokens" do
      session = create_terminal_session(agent_type: "codex")
      payload = build_otlp_log_payload(
        token: "wrong-token",
        input_tokens: 999, output_tokens: 999, model: "gpt-5.1-codex-mini"
      )

      result = @adapter.ingest_usage(payload, session)
      assert_equal :accepted, result
      assert_nil session.reload.usage_statistic
    end

    # =========================================================================
    # refresh! — proactive-refresh hook (wraps refresh_access_token!)
    # =========================================================================

    test "refresh! returns refreshed and persists the rotated token" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :codex, user: user, config_data: {
        "tokens" => { "access_token" => "old", "refresh_token" => "r1", "id_token" => "id1" }
      })
      stub_request(:post, Codex::Api::OAUTH_TOKEN_URL)
        .to_return(status: 200,
                   body: { access_token: "new", refresh_token: "r2", id_token: "id2" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal({ status: :refreshed, detail: nil }, @adapter.refresh!(credential))
      assert_equal "new", credential.reload.config_data.dig("tokens", "access_token")
    end

    test "refresh! returns error when the token endpoint fails" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :codex, user: user, config_data: {
        "tokens" => { "access_token" => "old", "refresh_token" => "r1" }
      })
      stub_request(:post, Codex::Api::OAUTH_TOKEN_URL).to_return(status: 400, body: "nope")

      result = @adapter.refresh!(credential)

      assert_equal :error, result[:status]
      assert_equal "codex token refresh failed", result[:detail]
    end

    test "refresh! returns error when no refresh token is present" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :codex, user: user, config_data: { "tokens" => {} })

      assert_equal :error, @adapter.refresh!(credential)[:status]
    end

    test "refresh_access_token! keeps the stored refresh_token when the server omits a rotated one" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :codex, user: user, config_data: {
        "tokens" => { "access_token" => "old", "refresh_token" => "keep-me", "id_token" => "keep-id" }
      })
      # Response rotates only the access token — no refresh_token/id_token echoed back.
      stub_request(:post, Codex::Api::OAUTH_TOKEN_URL)
        .to_return(status: 200, body: { access_token: "new" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      @adapter.refresh_access_token!(credential)

      tokens = credential.reload.config_data["tokens"]
      assert_equal "new", tokens["access_token"]
      assert_equal "keep-me", tokens["refresh_token"], "must not drop the stored refresh_token"
      assert_equal "keep-id", tokens["id_token"], "must not drop the stored id_token"
    end

    test "refresh_access_token! does not overwrite a concurrently-stored newer token" do
      user = create(:user, company: create(:company))
      newer = jwt_with_exp(1.hour.from_now.to_i)
      credential = create(:agent_credential, :codex, user: user, config_data: {
        "tokens" => { "access_token" => newer, "refresh_token" => "r1" }
      })
      # Server hands back a token that expires SOONER than the stored one — the
      # rotation guard must keep the fresher stored token.
      older = jwt_with_exp(1.minute.from_now.to_i)
      stub_request(:post, Codex::Api::OAUTH_TOKEN_URL)
        .to_return(status: 200, body: { access_token: older, refresh_token: "r2" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      returned = @adapter.refresh_access_token!(credential)

      assert_equal newer, returned
      assert_equal newer, credential.reload.config_data.dig("tokens", "access_token")
    end

    test "token_expires_at decodes the JWT exp (ms) from the access token" do
      exp = 2.hours.from_now.to_i
      credentials = { "tokens" => { "access_token" => jwt_with_exp(exp) } }
      assert_equal exp * 1000, @adapter.token_expires_at(credentials)
    end

    test "token_expires_at falls back to the id_token when the access token is opaque" do
      exp = 90.minutes.from_now.to_i
      credentials = { "tokens" => { "access_token" => "opaque", "id_token" => jwt_with_exp(exp) } }
      assert_equal exp * 1000, @adapter.token_expires_at(credentials)
    end

    test "token_expires_at returns nil when no token is a JWT" do
      assert_nil @adapter.token_expires_at({ "tokens" => { "access_token" => "opaque" } })
      assert_nil @adapter.token_expires_at({})
    end

    test "mcp_config escapes TOML-hostile characters in values" do
      server = OpenStruct.new(
        name: "ctx",
        transport: "streamable-http",
        url: "https://mcp.example.com",
        headers: { "Authorization" => 'Bearer a"b\\c' }
      )

      toml = @adapter.mcp_config([ server ])["/home/codex/.codex/config.toml"]

      # Quote and backslash inside the value are escaped, so the string stays a
      # single valid TOML basic string instead of corrupting the file.
      assert_includes toml, 'Bearer a\\"b\\\\c'
      assert_includes toml, 'url = "https://mcp.example.com"'
    end

    test "mcp_config emits the baked Playwright browsers path for stdio servers (task #340)" do
      # Codex does not forward the container environment to STDIO MCP servers, so the
      # browsers path must be written into config.toml explicitly or the Playwright
      # MCP cannot find the baked Chrome for Testing and fails with
      # "Browser chrome-for-testing is not installed".
      server = OpenStruct.new(
        name: "playwright",
        transport: "stdio",
        command: "npx @playwright/mcp",
        args: [ "--headless" ],
        env: {}
      )

      toml = @adapter.mcp_config([ server ])["/home/codex/.codex/config.toml"]

      # Build the expected env fragment through the adapter's own TOML escaper so
      # the assertion stays correct regardless of how special characters (the
      # hyphen in the path, spaces in the command) are escaped.
      key = @adapter.toml_string("PLAYWRIGHT_BROWSERS_PATH")
      val = @adapter.toml_string("/opt/playwright-browsers")
      assert_includes toml, "env = { #{key} = #{val} }"
    end

    test "mcp_config pins the Playwright MCP command to the baked version (task #340)" do
      server = OpenStruct.new(
        name: "playwright",
        transport: "stdio",
        command: "npx",
        args: [ "@playwright/mcp@latest", "--headless" ],
        env: {}
      )

      toml = @adapter.mcp_config([ server ])["/home/codex/.codex/config.toml"]

      pinned = @adapter.toml_string("@playwright/mcp@#{Agents::BaseAdapter::PLAYWRIGHT_MCP_VERSION}")
      assert_includes toml, "args = [#{pinned}, #{@adapter.toml_string("--headless")}]"
      # Emitted command cannot float independently of PLAYWRIGHT_MCP_VERSION.
      refute_includes toml, @adapter.toml_string("@playwright/mcp@latest")
    end

    # == Launch-time Credential Preflight ==

    # task #1327 (owner decision, board comment 8142): the preflight is a pure
    # existence + non-zero-size stat — no file content is ever read, so there is
    # no diagnostic to assert on and nothing to redact.
    test "credential_preflight accepts a non-empty auth file regardless of content" do
      content = { "tokens" => { "access_token" => "top-secret-access-value" } }.to_json
      runtime, container = preflight_runtime(content)

      result = @adapter.credential_preflight(runtime, container, "abc123")

      assert result[:valid]
      assert_nil result[:error_code]
    end

    test "credential_preflight rejects a missing auth file" do
      runtime, container = preflight_runtime(nil)

      result = @adapter.credential_preflight(runtime, container, "abc123")

      refute result[:valid]
      assert_equal "auth_file_missing", result[:error_code]
    end

    test "credential_preflight rejects a zero-byte auth file" do
      runtime, container = preflight_runtime("")

      result = @adapter.credential_preflight(runtime, container, "abc123")

      refute result[:valid]
      assert_equal "auth_file_empty", result[:error_code]
    end

    private

    def preflight_runtime(auth_content)
      filesystem = {}
      filesystem[@adapter.config_path] = auth_content unless auth_content.nil?
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "codex", filesystem: filesystem)
      [ runtime, runtime.resolve_container("abc123") ]
    end

    def codex_models_url
      "#{Codex::Api::MODELS_URL}?client_version=#{Codex::Api::CLIENT_VERSION}"
    end

    # Canned /codex/models response. `models` entries mirror the API shape the CLI
    # reads: `slug`, `visibility`, and an optional `upgrade` object naming the
    # migration target.
    def stub_codex_models(models)
      stub_request(:get, codex_models_url).to_return(codex_models_response(models))
    end

    def codex_models_response(models)
      { status: 200,
        body: { "models" => models }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    def codex_toml(workflow_config, credentials = { "tokens" => { "access_token" => "tok" } })
      @adapter.config_files(credentials, workflow_config)["/home/codex/.codex/config.toml"]
    end

    # Minimal unsigned JWT carrying an `exp` claim (seconds). Signature segment is
    # irrelevant — token_expires_at reads the payload without verifying.
    def jwt_with_exp(exp_seconds)
      header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
      payload = Base64.urlsafe_encode64({ exp: exp_seconds }.to_json, padding: false)
      "#{header}.#{payload}.sig"
    end

    def create_terminal_session(agent_type:)
      company = create(:company)
      user = create(:user, company: company)
      create(:terminal_session, agent_type: agent_type, state: "finished", user: user)
    end

    def build_otlp_mitm_log(token_data:, model:)
      body = build_otlp_metrics_json(token_data: token_data, model: model)
      mitm_request_line("/otlp/v1/metrics", body) + "\n" +
        mitm_response_line("/otlp/v1/metrics", 202) + "\n"
    end

    def build_otlp_metrics_json(token_data:, model:)
      data_points = token_data.map do |token_type, value|
        {
          "attributes" => [
            { "key" => "model", "value" => { "stringValue" => model } },
            { "key" => "token_type", "value" => { "stringValue" => token_type } }
          ],
          "sum" => value.to_f,
          "count" => 1
        }
      end

      {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "codex.turn.token_usage",
              "histogram" => {
                "dataPoints" => data_points,
                "aggregationTemporality" => 1
              }
            } ]
          } ]
        } ]
      }.to_json
    end

    def build_otlp_log_payload(token:, input_tokens:, output_tokens:, cached_tokens: 0, reasoning_tokens: 0, model: nil)
      attrs = [
        { "key" => "event.name", "value" => { "stringValue" => "codex.sse_event" } },
        { "key" => "input_token_count", "value" => { "intValue" => input_tokens } },
        { "key" => "output_token_count", "value" => { "intValue" => output_tokens } },
        { "key" => "cached_token_count", "value" => { "intValue" => cached_tokens } },
        { "key" => "reasoning_token_count", "value" => { "intValue" => reasoning_tokens } }
      ]
      attrs << { "key" => "model", "value" => { "stringValue" => model } } if model

      {
        "resourceLogs" => [ {
          "resource" => {
            "attributes" => [
              { "key" => "terminal_session_token", "value" => { "stringValue" => token } }
            ]
          },
          "scopeLogs" => [ {
            "logRecords" => [ {
              "timeUnixNano" => (Time.current.to_f * 1_000_000_000).to_i.to_s,
              "attributes" => attrs
            } ]
          } ]
        } ]
      }
    end

    def mitm_request_line(path, body_json)
      {
        "direction" => "request",
        "host" => "ab.chatgpt.com",
        "path" => path,
        "body_encoding" => "text",
        "body" => body_json,
        "ts" => Time.current.iso8601
      }.to_json
    end

    def mitm_response_line(path, status, body = "")
      {
        "direction" => "response",
        "host" => "chatgpt.com",
        "path" => path,
        "status_code" => status,
        "body_encoding" => "text",
        "body" => body,
        "ts" => Time.current.iso8601
      }.to_json
    end
  end
end
