# frozen_string_literal: true

require "test_helper"

module Agents
  class CopilotCliAdapterTest < ActiveSupport::TestCase
    TOKEN = "gho_copilottesttoken000000000000000000"

    setup do
      @adapter = CopilotCliAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "copilot_cli")
    end

    # config.json as `copilot login` leaves it with no keychain (measured on 1.0.108):
    # comment lines on top, and the token under two keys for one github.com account.
    def logged_in_config(token: TOKEN, host: "https://github.com", login: "octocat", kind: "githubDotCom")
      <<~JSONC
        // User settings belong in settings.json.
        // This file is managed automatically.
        #{{
          "trustedFolders" => [ "/workspace" ],
          "authTokens" => {
            "#{host}:#{login}:github" => { "token" => token },
            "#{host}:#{login}" => { "token" => token }
          },
          "loggedInUsers" => [ { "host" => host, "login" => login, "kind" => kind } ],
          "lastLoggedInUser" => { "host" => host, "login" => login }
        }.to_json}
      JSONC
    end

    # == Auth ==

    test "the watcher waits for config.json to hold tokens, which it does only after a login" do
      assert_equal "/home/copilot/.copilot/config.json", @adapter.auth_watch_path
      assert_equal [ %(__contains__:"authTokens") ], @adapter.auth_required_keys
    end

    test "a completed login is recognised through the comment lines config.json starts with" do
      assert @adapter.auth_complete?(logged_in_config)
      assert @adapter.auth_complete?(logged_in_config(token: "github_pat_11ABCDEFG0123456789abcdefghij"))
    end

    test "a config with no usable GitHub token is not a login" do
      refute @adapter.auth_complete?("")
      refute @adapter.auth_complete?(%(// managed\n{"trustedFolders": ["/workspace"]}))
      refute @adapter.auth_complete?(logged_in_config(token: "ghp_classicclassicclassicclassic00"))
      refute @adapter.auth_complete?(logged_in_config(kind: "entra"))
    end

    test "only the token and the account it belongs to are captured" do
      credentials = @adapter.extract_credentials(logged_in_config)

      assert_equal({ "token" => TOKEN, "host" => "https://github.com", "login" => "octocat",
                     "kind" => "githubDotCom", "source" => "device_flow" }, credentials)
      assert_equal "https://github.com:octocat", @adapter.credential_identity(credentials)
    end

    test "a pasted fine-grained token and a data-residency host are captured as such" do
      credentials = @adapter.extract_credentials(
        logged_in_config(token: "github_pat_11ABCDEFG0123456789abcdefghij", host: "https://octo.ghe.com", kind: "proxima")
      )

      assert_equal "fine_grained_pat", credentials["source"]
      assert_equal "https://octo.ghe.com", credentials["host"]
    end

    test "the login terminal is seeded with settings only, so config.json is the CLI's own" do
      files = @adapter.auth_setup_files

      assert_equal [ "/home/copilot/.copilot/settings.json" ], files.keys
      assert_equal true, JSON.parse(files.values.first)["storeTokenPlaintext"] # rubocop:disable Minitest/AssertTruthy
    end

    # == Session files ==

    test "a session gets the token in a private file and never in config.json" do
      credentials = @adapter.extract_credentials(logged_in_config)
      files = @adapter.config_files(credentials)

      assert_equal TOKEN, files["/home/copilot/.copilot/aixle-token"]
      assert_includes @adapter.private_file_paths, "/home/copilot/.copilot/aixle-token"
      assert_equal({ "trustedFolders" => [ "/workspace" ] }, JSON.parse(files["/home/copilot/.copilot/config.json"]))
      assert files.values.none? { |content| content != TOKEN && content.include?(TOKEN) }

      settings = JSON.parse(files["/home/copilot/.copilot/settings.json"])
      assert_equal true, settings["continueOnAutoMode"] # rubocop:disable Minitest/AssertTruthy
      assert_equal false, settings["autoUpdate"] # rubocop:disable Minitest/RefuteFalse
      # MCP tools stay in the model's own list instead of behind a tool search.
      assert_equal false, settings["toolSearch"] # rubocop:disable Minitest/RefuteFalse
      assert_equal({ "mcp" => false }, settings["dynamicRetrieval"])
    end

    test "a refreshed token is delivered as the token file alone" do
      assert_equal({ "/home/copilot/.copilot/aixle-token" => TOKEN }, @adapter.credential_files({ "token" => TOKEN }))
      assert_empty @adapter.credential_files({})
    end

    test "context and skills live in the Copilot home, where the CLI reads them in every directory" do
      assert_equal "/home/copilot/.copilot/copilot-instructions.md", @adapter.context_file_path
      assert_equal "github-copilot", @adapter.skills_agent_name
      assert_equal "/home/copilot/.copilot/skills", @adapter.skills_install_path
    end

    # == Logs ==

    test "session_log_paths collects the CLI's own transcript" do
      assert_equal [ "/var/log/context.log", "/home/copilot/.copilot/session-state/*/events.jsonl" ],
                   @adapter.session_log_paths
    end

    test "session_log_name folds the CLI's session id into the transcript's name" do
      assert_equal "33383f06-3dcf-40ee-b06a-d56671b4760d.events.jsonl",
                   @adapter.session_log_name(
                     "/home/copilot/.copilot/session-state/33383f06-3dcf-40ee-b06a-d56671b4760d/events.jsonl"
                   )
      assert_equal "context.log", @adapter.session_log_name("/var/log/context.log")
    end

    # == Launch ==

    test "the CLI gets its token from the file, in the shell that starts it" do
      command = @adapter.session_command(mode: "interactive")

      assert command.start_with?(%(COPILOT_GITHUB_TOKEN="$(cat /home/copilot/.copilot/aixle-token)" copilot ))
      assert_includes command, "--allow-all"
      assert_includes command, "--no-auto-update"
      assert_includes command, "--disable-builtin-mcps"
      assert_includes command, "--secret-env-vars=COPILOT_GITHUB_TOKEN"
      refute_includes command, "-i"
    end

    test "an automatic session ends on -i so the appended prompt becomes its value" do
      command = @adapter.session_command(mode: "non_interactive", model: "gpt-5.3-codex", effort: "high")

      assert_includes command, "--model gpt-5.3-codex"
      assert_includes command, "--reasoning-effort high"
      assert command.end_with?("--no-ask-user -i")
    end

    test "the session env routes telemetry to this session and pins the token's host" do
      create(:agent_credential, :copilot_cli, user: @user, company: @company)

      env = @adapter.default_env_vars(@session)

      assert_equal "true", env["COPILOT_OTEL_ENABLED"]
      assert_equal Settings.otel.endpoint.to_s, env["OTEL_EXPORTER_OTLP_ENDPOINT"]
      assert_includes env["OTEL_RESOURCE_ATTRIBUTES"], "terminal_session_token=#{@session.route_token}"
      assert_equal "github.com", env["COPILOT_GH_HOST"]
      refute env.key?("COPILOT_GITHUB_TOKEN")
    end

    test "a session with its own callback addresses reports to its own collector, or nowhere" do
      create(:agent_credential, :copilot_cli, user: @user, company: @company)

      assert_equal "http://otel.runner:4318",
                   @adapter.default_env_vars(@session, callbacks: { otel: "http://otel.runner:4318" })["OTEL_EXPORTER_OTLP_ENDPOINT"]

      env = @adapter.default_env_vars(@session, callbacks: { otel: nil })
      refute env.key?("OTEL_EXPORTER_OTLP_ENDPOINT")
      refute env.key?("COPILOT_OTEL_ENABLED")
    end

    # == MCP ==

    test "MCP servers are written in the CLI's own mcp-config.json shape" do
      remote = OpenStruct.new(name: "Aixle Tools", transport: "http", url: "http://web:4002/mcp",
                              headers: { "Authorization" => "Bearer x" })
      local = OpenStruct.new(name: "playwright", transport: "stdio", command: "npx", args: [ "@playwright/mcp" ], env: {})

      config = JSON.parse(@adapter.mcp_config([ remote, local ])["/home/copilot/.copilot/mcp-config.json"])
      servers = config["mcpServers"]

      assert_equal({ "type" => "http", "tools" => [ "*" ], "url" => "http://web:4002/mcp",
                     "headers" => { "Authorization" => "Bearer x" } }, servers[MCPServer.config_key_for("Aixle Tools")])
      assert_equal "local", servers["playwright"]["type"]
      assert_equal "npx", servers["playwright"]["command"]
      assert_equal "/opt/playwright-browsers", servers["playwright"].dig("env", "PLAYWRIGHT_BROWSERS_PATH")
    end

    # == Models ==

    test "until the catalogue is read from the CLI, the picker offers Auto alone" do
      result = @adapter.fetch_available_models_with_source({ "token" => TOKEN })

      assert_equal :fallback, result[:source]
      assert_equal [ "auto" ], result[:models].pluck(:model_id)
    end

    test "the catalogue the CLI reported is what the picker offers" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "copilot_cli")
      credential = create(:agent_credential, :copilot_cli, user: @user, company: @company)

      metadata = @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential, :auth)
      credential.update!(metadata: metadata)
      result = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)

      assert_equal "claude-sonnet-5.5", metadata[CopilotCliAdapter::DEFAULT_MODEL_METADATA_KEY]
      assert_equal :api, result[:source]
      assert_equal %w[auto claude-sonnet-5.5 gpt-5.3-codex], result[:models].pluck(:model_id)
      assert_equal "Claude Sonnet 5.5", result[:models].second[:display_name]
    end

    # Read off a staging account (1.0.108): the ACP model option lists Auto twice.
    test "a model the catalogue lists twice is offered once" do
      credential = create(:agent_credential, :copilot_cli, user: @user, company: @company,
                          metadata: { CopilotCliAdapter::MODELS_METADATA_KEY => [
                            { "id" => "auto", "name" => "Auto", "description" => "Let Copilot pick the best model" },
                            { "id" => "auto", "name" => "Auto", "description" => "Auto" },
                            { "id" => "claude-sonnet-5.5", "name" => "Claude Sonnet 5.5" }
                          ] })

      models = @adapter.fetch_available_models(credential.config_data, credential: credential)

      assert_equal %w[auto claude-sonnet-5.5], models.pluck(:model_id)
      assert_equal "Let Copilot pick the best model", models.first[:description]
    end

    test "a catalogue the CLI could not read leaves the stored one alone" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "copilot_cli")
      runtime.fail_exec(CopilotCliAdapter::MODELS_SCRIPT, stderr: "timed out waiting for the Copilot CLI", exit_code: 1)
      credential = create(:agent_credential, :copilot_cli, user: @user, company: @company)

      assert_empty @adapter.collect_credential_metadata(runtime, runtime.resolve_container("abc123"), credential, :session)
    end

    # == Usage ==

    # One model call from a real session (claude-haiku-4.5, 1.0.108): the chat span and the
    # invoke_agent span around it both carry the call's AI credits.
    def real_session_payload(token)
      span = lambda do |name, parent, attrs|
        { "name" => name, "spanId" => SecureRandom.hex(8), "parentSpanId" => parent,
          "startTimeUnixNano" => "1762752050750000000", "endTimeUnixNano" => "1762752052000000000",
          "attributes" => attrs.map { |k, v| { "key" => k, "value" => v.is_a?(Float) ? { "doubleValue" => v } : { "stringValue" => v.to_s } } } }
      end
      usage = { "gen_ai.usage.input_tokens" => "16746", "gen_ai.usage.output_tokens" => "55",
                "github.copilot.nano_aiu" => 2_120_500_000.0 }
      {
        "resourceSpans" => [ {
          "resource" => { "attributes" => [ { "key" => "terminal_session_token", "value" => { "stringValue" => token } } ] },
          "scopeSpans" => [ { "spans" => [
            span.call("chat claude-haiku-4.5", "727303b2f2ec1339",
                      usage.merge("gen_ai.operation.name" => "chat", "gen_ai.request.model" => "claude-haiku-4.5",
                                  "gen_ai.usage.cache_write.input_tokens" => "16736")),
            span.call("invoke_agent", "", usage.merge("gen_ai.operation.name" => "invoke_agent"))
          ] } ]
        } ]
      }
    end

    test "each model call is priced from the AI credits GitHub charged for it, once" do
      assert_equal :ok, @adapter.ingest_usage(real_session_payload(@session.route_token), @session)

      stat = @session.reload.usage_statistic
      assert_equal 10, stat.input_tokens
      assert_equal 55, stat.output_tokens
      assert_equal 16_736, stat.cache_write_tokens
      assert_in_delta 2.1205, stat.total_cents_precise.to_f, 0.0001
      assert_equal [ "claude-haiku-4.5" ], stat.models
      assert_equal "otlp_copilot", stat.source
      assert_equal "credits", stat.events_data.first["costBasis"]
      assert_equal 1_250, stat.events_data.first["durationMs"]
    end

    # A transcript captured from 1.0.108 against test/otlp_capture/mock.py, with one tool call.
    def transcript
      Rails.root.join("test/fixtures/files/transcripts/copilot_cli-1.0.108.events.jsonl").read
    end

    test "the transcript's prompt and tool call are kept for a project that shares prompts, its result is not" do
      @session.project.update!(settings: { "insights" => { "share_prompts" => true } })

      @adapter.collect_usage(@session, { "logs/22268fec.events.jsonl" => transcript, "logs/http.log" => "" })

      prompt = AgentPrompt.find_by!(terminal_session: @session)
      assert_equal [ "Read /tmp/capture.txt, then say hi. CAPTURE_TOOL", "transcript" ], [ prompt.text, prompt.source ]
      call = AgentToolCall.find_by!(terminal_session: @session)
      assert_equal [ "view", { "path" => "/tmp/capture.txt" }, true, prompt.prompt_ref ],
                   [ call.tool_name, call.arguments, call.success, call.prompt_ref ]
      assert_operator call.duration_ms, :>=, 0
      assert_not_includes call.attributes.to_json, "diff --git"
    end

    test "the transcript is not read for a project that does not share prompts" do
      @adapter.collect_usage(@session, { "logs/22268fec.events.jsonl" => transcript })

      assert_not AgentPrompt.exists?(terminal_session: @session)
    end

    test "a batch for another session is ignored" do
      assert_equal :accepted, @adapter.ingest_usage(real_session_payload("someone-else"), @session)
      assert_nil @session.reload.usage_statistic
    end
  end
end
