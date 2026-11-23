# frozen_string_literal: true

require "test_helper"

module Agents
  class AntigravityCliAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = AntigravityCliAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project)
    end

    test "uses the OAuth token file agy itself writes on login" do
      assert_equal "/home/antigravity/.gemini/antigravity-cli/antigravity-oauth-token", @adapter.config_path
      assert_equal @adapter.config_path, @adapter.auth_watch_path
      assert @adapter.auth_complete?('{"token":{"access_token":"tok-123"},"auth_method":"consumer"}')
      refute @adapter.auth_complete?('{"auth_method":"consumer"}')
      refute @adapter.auth_complete?("{}")
      assert_equal(
        { "access_token" => "tok-123", "refresh_token" => "refresh-123", "auth_method" => "consumer" },
        @adapter.extract_credentials(
          '{"token":{"access_token":"tok-123","refresh_token":"refresh-123","other":"ignored"},"auth_method":"consumer"}'
        )
      )
    end

    test "extract_credentials returns nothing for a file with no token block yet" do
      assert_equal({}, @adapter.extract_credentials('{"enableTelemetry":false,"trustedWorkspaces":["/workspace"]}'))
    end

    test "writes OAuth settings and credentials in the exact shape agy itself writes" do
      credentials = { "access_token" => "tok-123", "refresh_token" => "refresh-123", "auth_method" => "consumer" }
      files = @adapter.config_files(credentials)
      settings = JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"])
      assert_equal({ "showTips" => false, "trustedWorkspaces" => [ "/workspace" ], "altScreenMode" => "never" }, settings)
      assert_equal(
        { "token" => { "access_token" => "tok-123", "refresh_token" => "refresh-123" }, "auth_method" => "consumer" },
        JSON.parse(files[@adapter.config_path])
      )
    end

    test "marks a consumer login's first-run onboarding as done, as agy itself records it" do
      files = @adapter.config_files({ "access_token" => "tok-123", "auth_method" => "consumer" })

      assert_equal(
        { "consumerOnboardingComplete" => true, "enterpriseOnboardingComplete" => false, "onboardingComplete" => true },
        JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/cache/onboarding.json"])
      )
    end

    test "installs a hook per lifecycle event that forwards it to the session's collector" do
      files = @adapter.config_files({ "access_token" => "tok-123" }, otel_endpoint: "http://otlp-ingest:4318", full_telemetry: true)
      hooks = JSON.parse(files["/home/antigravity/.gemini/config/hooks.json"]).fetch("aixle-telemetry")

      assert_equal %w[SessionStart PreInvocation PostInvocation PreToolUse PostToolUse Stop], hooks.keys
      assert_equal "python3 -I /opt/mitm/otlp_hook.py antigravity-cli Stop || true",
                   hooks["Stop"].sole["command"]
      tool_hook = hooks["PreToolUse"].sole
      assert_equal "*", tool_hook["matcher"]
      assert_equal "python3 -I /opt/mitm/otlp_hook.py antigravity-cli PreToolUse || true",
                   tool_hook["hooks"].sole["command"]
    end

    test "installs no hooks without full telemetry" do
      files = @adapter.config_files({ "access_token" => "tok-123" }, otel_endpoint: "http://otlp-ingest:4318")

      assert_not_includes files.keys, "/home/antigravity/.gemini/config/hooks.json"
    end

    test "leaves onboarding to agy for a login that is not a consumer one" do
      files = @adapter.config_files({ "access_token" => "tok-123", "auth_method" => "gcp" })

      assert_not_includes files.keys, "/home/antigravity/.gemini/antigravity-cli/cache/onboarding.json"
    end

    # Per review feedback, the auth terminal drives the real `agy` CLI directly
    # (its own interactive login, confirmed offering Google OAuth or a Google
    # Cloud project — both a real human completes themselves) rather than a
    # backend-written script; only the pre-login settings file is seeded upfront.
    test "seeds only OAuth-compatible settings before login, no bespoke script" do
      files = @adapter.auth_setup_files
      assert_equal({ "showTips" => false, "trustedWorkspaces" => [ "/workspace" ], "altScreenMode" => "never" },
                   JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"]))
      assert_equal [ "/home/antigravity/.gemini/antigravity-cli/settings.json" ], files.keys
    end

    test "drives the auth terminal through the bare CLI, same as every other adapter" do
      assert_equal [], @adapter.auth_launch_commands_for("agent")
    end

    test "runs automatic sessions in the TUI, the prompt submitted by -i" do
      assert_equal "agy --dangerously-skip-permissions", @adapter.session_command(mode: "interactive")
      assert_equal "agy --dangerously-skip-permissions", @adapter.session_command(mode: "non_interactive")
      assert_equal '-i "$(cat /tmp/.aixle-prompt)"', @adapter.prompt_argument('"$(cat /tmp/.aixle-prompt)"')
    end

    # Task #324: the model id carries the effort, and in the TUI a level agy cannot apply,
    # like a model the account lacks, silently runs the default model instead.
    test "session_command never passes a reasoning effort, and the model is checked before launch" do
      assert_equal "agy --model claude-sonnet-4-6 --dangerously-skip-permissions",
                   @adapter.session_command(mode: "non_interactive", model: "claude-sonnet-4-6", effort: "high")
      assert_predicate @adapter, :runs_default_model_for_unknown?
    end

    test "fetches agent models from the authenticated Antigravity catalogue in API order" do
      stub = stub_request(:post, Antigravity::Api::MODELS_URL)
             .with(
               headers: { "Authorization" => "Bearer tok-123", "Content-Type" => "application/json",
                          "User-Agent" => "antigravity/cli/#{AgentRuntime.fetch(:antigravity_cli).cli_version}" },
               body: { project: Antigravity::Api::CONSUMER_PROJECT }.to_json
             )
             .to_return(
               status: 200,
               body: {
                 models: {
                   "gemini-pro-agent" => { displayName: "Gemini Pro" },
                   "claude-sonnet-4-6" => { displayName: "Claude Sonnet 4.6" },
                   "image-model" => { displayName: "Image model" },
                   "gemini-4-neon-disabled" => { displayName: "Gemini 4 Neon", disabled: true }
                 },
                 agentModelSorts: [ { groups: [ { modelIds: %w[claude-sonnet-4-6 gemini-pro-agent missing-model
                                                               gemini-4-neon-disabled] } ] } ]
               }.to_json
             )

      result = @adapter.fetch_available_models_with_source({ "access_token" => "tok-123" })

      assert_requested stub
      assert_equal :api, result[:source]
      assert_equal %w[claude-sonnet-4-6 gemini-pro-agent], result[:models].pluck(:model_id)
      assert_equal [ "Claude Sonnet 4.6", "Gemini Pro" ], result[:models].pluck(:display_name)
    end

    test "decodes a gzip-compressed Antigravity catalogue" do
      payload = { models: { "gemini-pro-agent" => { displayName: "Gemini Pro" } },
                  agentModelSorts: [ { groups: [ { modelIds: [ "gemini-pro-agent" ] } ] } ] }.to_json
      compressed = StringIO.new
      Zlib::GzipWriter.wrap(compressed) { |gzip| gzip.write(payload) }
      stub_request(:post, Antigravity::Api::MODELS_URL)
        .to_return(status: 200, body: compressed.string, headers: { "Content-Encoding" => "gzip" })

      result = @adapter.fetch_available_models_with_source({ "access_token" => "tok-123" })

      assert_equal :api, result[:source]
      assert_equal [ "gemini-pro-agent" ], result[:models].pluck(:model_id)
    end

    test "offers the fallback Antigravity model catalogue without an access token" do
      result = @adapter.fetch_available_models_with_source({})

      assert_equal :fallback, result[:source]
      assert_includes result[:models],
                      { model_id: "gemini-3.8-flash-medium", display_name: "Gemini 3.8 Flash (Medium)" }
      assert_includes result[:models],
                      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" }
      assert_includes result[:models],
                      { model_id: "gpt-oss-120b-medium", display_name: "GPT-OSS 120B (Medium)" }
    end

    test "fallback catalogue offers the supported replacement, not the deprecated Gemini 3.1 Pro id" do
      result = @adapter.fetch_available_models_with_source({})

      model_ids = result[:models].pluck(:model_id)
      assert_includes model_ids, "gemini-pro-agent"
      refute_includes model_ids, "gemini-3.1-pro-high"
    end

    test "every observed live catalogue model has fallback metadata and configured pricing" do
      observed_model_ids = %w[
        gemini-3.8-flash-high gemini-3.8-flash-medium gemini-3.8-flash-low
        gemini-3.7-flash-high gemini-3.7-flash-medium gemini-3.7-flash-low
        gemini-3.6-flash-high gemini-3.6-flash-medium gemini-3.6-flash-low
        gemini-pro-agent gemini-3.1-pro-low claude-sonnet-4-6 claude-opus-4-6-thinking
        gpt-oss-120b-medium
      ]

      assert_empty observed_model_ids - AntigravityCliAdapter::FALLBACK_MODELS.pluck(:model_id)
      assert_empty observed_model_ids - AntigravityCliAdapter::MODEL_PRICING.keys
    end

    test "prices the Gemini 4 Argon and Claude 5.5 models the CLI offers since 1.4.7" do
      model_ids = %w[gemini-4-argon-high gemini-4-argon-medium gemini-4-argon-low] +
                  %w[opus sonnet].product(%w[max high medium low]).map { |family, effort| "claude-#{family}-5-5-#{effort}" }

      assert_empty model_ids - AntigravityCliAdapter::MODEL_PRICING.keys
      assert_in_delta 300.0, @adapter.send(:usage_cost_cents, "claude-sonnet-5-5-high", 1_000_000, 100_000, 0)
    end

    test "warns when a catalogue model has no configured pricing" do
      Rails.logger.expects(:warn)
                  .with('[AntigravityCliAdapter] no configured pricing for model "new-unpriced-model"')

      cost = @adapter.send(:usage_cost_cents, "new-unpriced-model", 100, 20, 0)

      assert_in_delta 0.0, cost
    end

    test "falls back when the Antigravity catalogue request fails" do
      stub_request(:post, Antigravity::Api::MODELS_URL).to_return(status: 401)

      result = @adapter.fetch_available_models_with_source({ "access_token" => "expired" })

      assert_equal :fallback, result[:source]
      assert_equal AntigravityCliAdapter::FALLBACK_MODELS, result[:models]
    end

    test "omits the model flag when none is selected so Antigravity uses its default" do
      assert_equal "agy --dangerously-skip-permissions", @adapter.session_command(mode: "non_interactive", model: nil)
    end

    test "generates Antigravity MCP schema" do
      server = stub(name: "Remote API", transport: "http", url: "https://example.test/mcp", headers: { "X-Key" => "x" })
      config = JSON.parse(@adapter.mcp_config([ server ]).values.first)
      entry = config.dig("mcpServers", MCPServer.config_key_for(server.name))
      assert_equal "https://example.test/mcp", entry["serverUrl"]
      assert_equal({ "X-Key" => "x" }, entry["headers"])
    end

    test "default_env_vars hides the CLI logo, keeps the pinned CLI, and points the proxy log at Google's hosts" do
      env = @adapter.default_env_vars(@session, callbacks: hosted_callbacks)

      assert_equal "1", env["AGY_CLI_HIDE_LOGO"]
      assert_equal "true", env["AGY_CLI_DISABLE_AUTO_UPDATE"]
      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal "googleapis.com,google.com", env["MITM_TRACKED_DOMAINS"]
      # Still no credential in the environment: the token travels in the config file.
      assert_nil env.values.find { |v| v.to_s.include?("access_token") }
    end

    # Under its own name, not OTEL_RESOURCE_ATTRIBUTES: agy's telemetry goes to Google, and
    # an SDK that reads that variable would send the session key along.
    test "default_env_vars gives the hooks the collector and the session, with full telemetry and a collector" do
      plain_env = @adapter.default_env_vars(@session, callbacks: hosted_callbacks)
      @session.stubs(:full_telemetry?).returns(true)
      env = @adapter.default_env_vars(@session, callbacks: hosted_callbacks)
      runner_env = @adapter.default_env_vars(@session, callbacks: hosted_callbacks.merge(otel: nil))

      assert_equal [ Settings.otel.endpoint, UsageStatistics::SessionKey.resource_attributes(@session) ],
                   env.values_at("AIXLE_OTLP_ENDPOINT", "AIXLE_OTLP_RESOURCE_ATTRIBUTES")
      assert_not_includes env.keys, "OTEL_RESOURCE_ATTRIBUTES"
      assert_empty runner_env.keys.grep(/\AAIXLE_OTLP/)
      assert_empty plain_env.keys.grep(/\AAIXLE_OTLP/)
    end

    # 51 production sessions in the 30 days to 2026-09-17 produced zero HTTP records,
    # because the proxy wrote the log and nothing ever collected it — which is why the
    # runtime's refresh protocol is still something read out of the binary rather than
    # observed.
    test "session_log_paths collects the proxy log and every conversation's transcript" do
      assert_includes @adapter.session_log_paths, "/var/log/mitm/http.log"
      assert_includes @adapter.session_log_paths, AntigravityCliAdapter::TRANSCRIPT_GLOB
    end

    test "a transcript is stored under its conversation id" do
      path = "/home/antigravity/.gemini/antigravity-cli/brain/5f1c-77/.system_generated/logs/transcript.jsonl"

      assert_equal "5f1c-77.transcript.jsonl", @adapter.session_log_name(path)
      assert_equal "http.log", @adapter.session_log_name("/var/log/mitm/http.log")
    end

    def transcript = file_fixture("antigravity/transcript.jsonl").read

    # agy 1.5.13: input excludes cache reads and output includes thinking, the same totals
    # print mode's `result` event reported for the run.
    test "collect_usage sums every model call in the transcripts and prices each bucket on its own" do
      @session.update!(agent_type: "antigravity_cli", requested_model: "gemini-3.8-flash-high")

      @adapter.collect_usage(@session, { "logs/conv-1.transcript.jsonl" => transcript,
                                         "logs/http.log" => "not a transcript" })

      stat = @session.reload.usage_statistic
      assert_equal 12_657, stat.input_tokens
      assert_equal 202, stat.output_tokens
      assert_equal 8_312, stat.cache_read_tokens
      assert_equal [ "gemini-3.8-flash-high" ], stat.models
      assert_equal "antigravity_transcript", stat.source
      assert_in_delta(((12_657 * 0.75) + (8_312 * 0.075) + (202 * 3.75)) / 10_000.0, stat.total_cents_precise.to_f, 0.0001)
    end

    test "collect_usage keeps each model apart and adds conversations together" do
      claude = { type: "PLANNER_RESPONSE", model: "claude-sonnet-4-6", input_tokens: 1_000_000,
                 cache_read_tokens: 200_000, output_tokens: 100_000 }.to_json

      @adapter.collect_usage(@session, { "logs/a.transcript.jsonl" => transcript,
                                         "logs/b.transcript.jsonl" => "#{claude}\n" })

      stat = @session.reload.usage_statistic
      assert_equal %w[claude-sonnet-4-6 gemini-3.8-flash-high], stat.models.sort
      assert_equal 1_012_657, stat.input_tokens
      assert_equal 2, stat.events_count
    end

    test "collect_usage leaves no statistic without a transcript or without billable calls" do
      @adapter.collect_usage(@session, { "logs/http.log" => "x" })
      @adapter.collect_usage(@session, { "logs/a.transcript.jsonl" => "{\"type\":\"USER_INPUT\"}\nnot json\n[]\n" })

      assert_nil @session.reload.usage_statistic
    end

    test "collect_usage is idempotent across a cleanup retry" do
      @session.update!(agent_type: "antigravity_cli", requested_model: "gemini-3.8-flash-high")
      artifacts = { "logs/conv-1.transcript.jsonl" => transcript }

      # Cleanup re-fetches the session on every retry attempt (TerminalSession.find in
      # AgentSessionStrategy#before_cleanup), so the second call sees a fresh row.
      @adapter.collect_usage(@session, artifacts)
      @adapter.collect_usage(TerminalSession.find(@session.id), artifacts)

      assert_equal 12_657, @session.reload.usage_statistic.input_tokens
    end

    test "credential_preflight accepts a valid OAuth token" do
      runtime, container = preflight_runtime(
        { "token" => { "access_token" => "tok-123" }, "auth_method" => "consumer" }.to_json
      )

      result = @adapter.credential_preflight(runtime, container, "abc123")

      assert result[:valid]
      assert_nil result[:error_code]
    end

    test "credential_preflight rejects a migrated API-key credential" do
      runtime, container = preflight_runtime({ "token" => { "api_key" => "legacy-key" } }.to_json)

      result = @adapter.credential_preflight(runtime, container, "abc123")

      refute result[:valid]
      assert_equal "oauth_token_missing", result[:error_code]
    end

    # == Server-side refresh ==
    #
    # Google installed-app OAuth, measured on a production credential: a 3599s access
    # token and no rotated refresh token in the response.

    def consumer_credential(auth_method: "consumer", refresh_token: "rt-1")
      create(:agent_credential, user: @user, agent_type: "antigravity_cli", config_data: {
        "access_token" => "at-old", "refresh_token" => refresh_token, "token_type" => "Bearer",
        "expiry" => 5.minutes.from_now.utc.iso8601(9), "auth_method" => auth_method
      }.compact)
    end

    test "refresh! renews a consumer login with agy's OAuth client and keeps the refresh token" do
      credential = consumer_credential
      request = stub_request(:post, AntigravityCliAdapter::GOOGLE_TOKEN_URL)
        .with(body: { grant_type: "refresh_token", refresh_token: "rt-1",
                      client_id: Settings.agents.antigravity.oauth_client_id,
                      client_secret: Settings.agents.antigravity.oauth_client_secret })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { access_token: "at-new", expires_in: 3599, token_type: "Bearer", scope: "openid" }.to_json)

      assert_equal :refreshed, @adapter.refresh!(credential)[:status]

      assert_requested request
      stored = credential.reload.config_data
      assert_equal "at-new", stored["access_token"]
      assert_equal "rt-1", stored["refresh_token"]
      assert_in_delta 1.hour.from_now.to_i, credential.expires_at.to_i, 5
      assert_equal "at-new", JSON.parse(@adapter.generate_config(stored).to_json).dig("token", "access_token")
    end

    test "refresh! treats a revoked grant as permanent" do
      credential = consumer_credential
      stub_request(:post, AntigravityCliAdapter::GOOGLE_TOKEN_URL)
        .to_return(status: 400, headers: { "Content-Type" => "application/json" },
                   body: { error: "invalid_grant", error_description: "Token has been expired or revoked." }.to_json)

      result = @adapter.refresh!(credential)

      assert_equal :error, result[:status]
      assert result[:permanent]
    end

    # agy's other embedded client belongs to the Cloud-project login, unverified — so that
    # login publishes no expiry and is left to the CLI rather than refreshed with a guess.
    test "a login other than consumer publishes no expiry and is not refreshed server-side" do
      credential = consumer_credential(auth_method: "cloud_project")

      assert_nil credential.expires_at
      assert_equal :not_needed, @adapter.refresh!(credential)[:status]
    end

    # == Write-back from a container ==

    def container_login(access_token:, expiry:)
      { "access_token" => access_token, "refresh_token" => "rt-1", "token_type" => "Bearer",
        "expiry" => expiry.utc.iso8601(9), "auth_method" => "consumer" }
    end

    # A session that started before the user signed in again still holds the old token
    # when it ends. Taking it back would undo the new login.
    test "a container's older token does not replace a newer stored login" do
      stored = container_login(access_token: "at-new", expiry: 1.hour.from_now)
      older = container_login(access_token: "at-old", expiry: 30.minutes.from_now)

      assert_equal stored, @adapter.merge_container_credentials(stored, older, credential_id: 42)
    end

    test "a token the container renewed replaces the stored one" do
      stored = container_login(access_token: "at-old", expiry: 5.minutes.from_now)
      renewed = container_login(access_token: "at-new", expiry: 1.hour.from_now)

      assert_equal "at-new", @adapter.merge_container_credentials(stored, renewed, credential_id: 42)["access_token"]
    end

    # == Remaining-quota snapshot ==

    def usage_probe_runtime
      ContainerRuntime::FakeRuntime.new(agent_type: "antigravity_cli", filesystem: {})
    end

    test "collect_credential_metadata stores the /usage probe as a snapshot" do
      credential = consumer_credential
      runtime = usage_probe_runtime
      container = runtime.resolve_container("abc123")

      extras = @adapter.collect_credential_metadata(runtime, container, credential, :session)

      snapshot = extras[AntigravityCliAdapter::SUBSCRIPTION_USAGE_KEY]
      assert snapshot, "expected a subscription_usage snapshot"
      assert snapshot["fetched_at"].present?

      windows = snapshot["windows"]
      assert_equal %w[gemini-weekly 3p-weekly], windows.map { |w| w[:key] }

      gemini = windows.find { |w| w[:key] == "gemini-weekly" }
      assert_equal "Gemini Models", gemini[:label]
      assert_in_delta 0.0, gemini[:utilization]
      assert_equal "2026-11-23T00:49:24Z", gemini[:resets_at]
      assert_equal 10_080, gemini[:window_duration_mins]

      claude = windows.find { |w| w[:key] == "3p-weekly" }
      assert_equal "Claude and GPT models", claude[:label]
      assert_in_delta 0.0, claude[:utilization]
      assert_equal "2026-11-23T00:49:24Z", claude[:resets_at]
      assert_equal 10_080, claude[:window_duration_mins]

      assert_equal [ AntigravityCliAdapter::USAGE_PROBE_COMMAND ], runtime.execs
    end

    test "usage_windows_from_probe qualifies buckets and skips disabled ones when a group has several" do
      stdout = {
        "status" => "SUCCESS",
        "command" => { "name" => "usage", "data" => {
          "groups" => [ { "name" => "Gemini Models", "buckets" => [
            { "id" => "gemini-weekly", "name" => "Weekly", "window" => "weekly",
              "remaining_fraction" => 0.5, "reset_time" => "2026-11-23T00:49:24Z" },
            { "id" => "3p-5h", "name" => "5 hours", "window" => "5h",
              "remaining_fraction" => 0.5, "reset_time" => "2026-11-23T00:49:24Z" },
            { "id" => "disabled-pool", "window" => "weekly", "remaining_fraction" => 0, "disabled" => true }
          ] } ]
        } }
      }.to_json

      windows = @adapter.send(:usage_windows_from_probe, stdout)

      assert_equal %w[gemini-weekly 3p-5h], windows.map { |w| w[:key] }
      assert_equal [ "Gemini Models · Weekly", "Gemini Models · 5 hours" ], windows.map { |w| w[:label] }
    end

    test "collect_credential_metadata writes nothing on a non-session phase or a failed probe" do
      credential = consumer_credential
      runtime = usage_probe_runtime
      container = runtime.resolve_container("abc123")

      assert_equal({}, @adapter.collect_credential_metadata(runtime, container, credential, :auth))

      runtime.fail_exec("/usage", exit_code: 1)
      assert_equal({}, @adapter.collect_credential_metadata(runtime, container, credential, :session))
    end

    test "fetch_subscription_usage_from_snapshot reads the stored snapshot" do
      credential = consumer_credential
      credential.update!(metadata: {
        "subscription_usage" => {
          "fetched_at" => "2027-01-15T00:00:00Z",
          "windows" => [
            { "key" => "gemini-weekly", "label" => "Gemini · Weekly", "utilization" => 40.0,
              "resets_at" => "2027-01-15T00:00:00Z", "window_duration_mins" => 10_080 }
          ]
        }
      })

      usage = @adapter.fetch_subscription_usage_from_snapshot(credential)

      assert_equal "ok", usage[:status]
      assert_equal "2027-01-15T00:00:00Z", usage[:fetched_at]
      assert_equal [ "gemini-weekly" ], usage[:windows].map { |w| w[:key] }
      assert_equal "Gemini · Weekly", usage[:windows].first[:label]
      assert_in_delta 40.0, usage[:windows].first[:utilization]
    end

    test "fetch_subscription_usage_from_snapshot drops windows whose reset has already passed" do
      credential = consumer_credential
      credential.update!(metadata: {
        "subscription_usage" => {
          "fetched_at" => "2026-08-21T12:00:00Z",
          "windows" => [
            { "key" => "gemini-weekly", "utilization" => 95.0,
              "resets_at" => "2026-08-21T12:00:00Z", "window_duration_mins" => 10_080 }
          ]
        }
      })

      assert_nil @adapter.fetch_subscription_usage_from_snapshot(credential)
    end

    test "fetch_subscription_usage_from_snapshot returns nil without a snapshot" do
      assert_nil @adapter.fetch_subscription_usage_from_snapshot(consumer_credential)
    end

    test "collect_credential_metadata_on_workflow_step? is true so workflow steps probe the quota" do
      assert @adapter.collect_credential_metadata_on_workflow_step?
    end

    private

    def preflight_runtime(auth_content)
      filesystem = {}
      filesystem[@adapter.config_path] = auth_content unless auth_content.nil?
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "antigravity_cli", filesystem: filesystem)
      [ runtime, runtime.resolve_container("abc123") ]
    end
  end
end
