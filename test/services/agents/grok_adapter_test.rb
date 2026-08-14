# frozen_string_literal: true

require "test_helper"

module Agents
  class GrokAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = GrokAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project, agent_type: "grok")
    end

    # A real auth.json is a map of auth scope => entry, keyed by issuer, with the
    # bearer token under "key".
    def oauth_auth_json(expires_at: nil)
      entry = { "key" => "grok-session-token", "token_type" => "Bearer" }
      entry["expires_at"] = expires_at if expires_at
      { GrokAdapter::OAUTH_SCOPE => entry }.to_json
    end

    def api_key_auth_json(key = "xai-test-key")
      { GrokAdapter::API_KEY_SCOPE => { "key" => key } }.to_json
    end

    # == Paths ==

    test "config_path is auth.json in the grok home" do
      assert_equal "/home/grok/.grok/auth.json", @adapter.config_path
    end

    test "home_dir returns grok home" do
      assert_equal "/home/grok", @adapter.home_dir
    end

    test "auth_watch_path and auth_file_paths both point at auth.json" do
      assert_equal "/home/grok/.grok/auth.json", @adapter.auth_watch_path
      assert_equal [ "/home/grok/.grok/auth.json" ], @adapter.auth_file_paths
    end

    test "context file is a home-level rule file so /workspace stays clean" do
      assert_equal "/home/grok/.grok/rules/aixle-session-context.md", @adapter.context_file_path
    end

    test "skills install into the directory the skills CLI uses for the grok agent" do
      assert_equal "grok", @adapter.skills_agent_name
      assert_equal "/home/grok/.grok/skills", @adapter.skills_install_path
    end

    # == Auth completion ==

    # auth.json's keys are issuer URLs full of dots, which the watcher's dotted-path
    # lookup cannot address — hence the existence sentinel, with the real check server-side.
    test "auth_required_keys uses the existence sentinel" do
      assert_equal %w[__present__], @adapter.auth_required_keys
    end

    test "auth_complete? is true once a scope entry carries a token" do
      assert @adapter.auth_complete?(oauth_auth_json)
      assert @adapter.auth_complete?(api_key_auth_json)
    end

    test "auth_complete? is false for blank, non-JSON, or tokenless content" do
      refute @adapter.auth_complete?("")
      refute @adapter.auth_complete?("   ")
      refute @adapter.auth_complete?("not json at all")
      refute @adapter.auth_complete?("{}")
      refute @adapter.auth_complete?({ GrokAdapter::OAUTH_SCOPE => { "token_type" => "Bearer" } }.to_json)
      refute @adapter.auth_complete?({ GrokAdapter::OAUTH_SCOPE => { "key" => "" } }.to_json)
    end

    # == Credential extraction ==

    test "extract_credentials keeps the scope map so it can be written back verbatim" do
      credentials = @adapter.extract_credentials(oauth_auth_json)

      assert_equal({ "key" => "grok-session-token", "token_type" => "Bearer" },
                   credentials.dig("auth", GrokAdapter::OAUTH_SCOPE))
      assert_nil credentials["api_key"]
    end

    test "extract_credentials lifts an API-key login out as a flat api_key" do
      credentials = @adapter.extract_credentials(api_key_auth_json)

      assert_equal "xai-test-key", credentials["api_key"]
      assert_equal "xai-test-key", credentials.dig("auth", GrokAdapter::API_KEY_SCOPE, "key")
    end

    test "extract_credentials drops scope entries with no token" do
      content = {
        GrokAdapter::OAUTH_SCOPE => { "key" => "real" },
        "https://legacy.example/scope" => { "token_type" => "Bearer" }
      }.to_json

      assert_equal [ GrokAdapter::OAUTH_SCOPE ], @adapter.extract_credentials(content)["auth"].keys
    end

    test "extract_credentials returns an empty hash when nothing was captured" do
      assert_equal({}, @adapter.extract_credentials("{}"))
    end

    # == Config files ==

    test "config_files writes auth.json plus a config.toml that pre-answers every prompt" do
      files = @adapter.config_files(@adapter.extract_credentials(oauth_auth_json))

      assert_equal({ GrokAdapter::OAUTH_SCOPE => { "key" => "grok-session-token", "token_type" => "Bearer" } },
                   JSON.parse(files["/home/grok/.grok/auth.json"]))

      toml = files["/home/grok/.grok/config.toml"]
      assert_match(/permission_mode = "always-approve"/, toml)
      assert_match(/\[folder_trust\]\nenabled = false/, toml)
      assert_match(/auto_update = false/, toml)
      assert_match(/telemetry = false/, toml)
      refute_match(/\[models\]/, toml)
    end

    test "config_files pins the session model in config.toml when one is requested" do
      toml = @adapter.config_files({ "auth" => {} }, { model: "grok-4.6" })["/home/grok/.grok/config.toml"]

      assert_match(/\[models\]\ndefault = "grok-4\.6"/, toml)
    end

    test "config_files omits auth.json when the credential holds no scopes" do
      files = @adapter.config_files({})

      refute_includes files.keys, "/home/grok/.grok/auth.json"
      assert_includes files.keys, "/home/grok/.grok/config.toml"
    end

    # The login terminal gets the same non-blocking settings, minus any model pin —
    # there is no credential yet to pin one against.
    test "auth_setup_files seeds config.toml before the login flow starts" do
      files = @adapter.auth_setup_files

      assert_equal [ "/home/grok/.grok/config.toml" ], files.keys
      assert_match(/auto_update = false/, files["/home/grok/.grok/config.toml"])
      refute_match(/\[models\]/, files["/home/grok/.grok/config.toml"])
    end

    # == Session command ==

    test "session_command runs the CLI in always-approve mode" do
      assert_equal "grok --yolo", @adapter.session_command(mode: "interactive")
      assert_equal "grok --yolo", @adapter.session_command(mode: "non_interactive", prompt: "do it")
    end

    test "session_command shell-escapes the requested model" do
      assert_equal "grok --yolo --model grok-4.5", @adapter.session_command(mode: "interactive", model: "grok-4.5")
      assert_equal "grok --yolo --model grok\\ 4.5\\;rm", @adapter.session_command(mode: "interactive", model: "grok 4.5;rm")
    end

    # == Environment ==

    # API keys are per company so the vendor bill lands on the company that ran the
    # session. Injecting another company's key would spend its quota here.
    test "default_env_vars injects the API key of the session's company only" do
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)
      create(:agent_credential, user: @user, company: other_company, agent_type: "grok",
                                config_data: { "api_key" => "other-tenant-key" })

      assert_nil @adapter.default_env_vars(@session)["XAI_API_KEY"]

      create(:agent_credential, user: @user, company: @company, agent_type: "grok",
                                config_data: { "api_key" => "mine" })

      assert_equal "mine", @adapter.default_env_vars(@session)["XAI_API_KEY"]
    end

    test "default_env_vars tracks x.ai traffic through the MITM proxy" do
      env = @adapter.default_env_vars(@session)

      assert_equal "x.ai", env["MITM_TRACKED_DOMAINS"]
      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal [ "x.ai" ], @adapter.mitm_tracked_domains
      assert_includes @adapter.session_log_paths, "/var/log/mitm/http.log"
    end

    # XAI_API_KEY outranks a stored session token in the CLI's own credential
    # resolution, so a stray key would silently bill a different xAI account.
    test "conflicting_env_keys drops a stray API key unless the credential is an API-key login" do
      assert_equal %w[XAI_API_KEY], @adapter.conflicting_env_keys(@adapter.extract_credentials(oauth_auth_json))
      assert_equal [], @adapter.conflicting_env_keys(@adapter.extract_credentials(api_key_auth_json))
    end

    # == Token expiry ==

    test "token_expires_at reads the soonest scope expiry in every plausible format" do
      iso = "2026-08-14T12:00:00Z"
      expected = Time.zone.parse(iso).to_i * 1000

      assert_equal expected, @adapter.token_expires_at(@adapter.extract_credentials(oauth_auth_json(expires_at: iso)))
      assert_equal expected, @adapter.token_expires_at(@adapter.extract_credentials(oauth_auth_json(expires_at: expected / 1000)))
      assert_equal expected, @adapter.token_expires_at(@adapter.extract_credentials(oauth_auth_json(expires_at: expected)))
    end

    test "token_expires_at takes the soonest expiry across scopes" do
      soon = Time.zone.parse("2026-08-14T12:00:00Z").to_i
      later = Time.zone.parse("2026-09-14T12:00:00Z").to_i
      credentials = { "auth" => {
        "scope-a" => { "key" => "a", "expires_at" => later },
        "scope-b" => { "key" => "b", "expires_at" => soon }
      } }

      assert_equal soon * 1000, @adapter.token_expires_at(credentials)
    end

    # An absent or unrecognisable expiry must degrade to "no expiry known" rather than
    # to a bogus value that would make AgentCredential.active skip a working credential.
    test "token_expires_at is nil when no scope carries a usable expiry" do
      assert_nil @adapter.token_expires_at(@adapter.extract_credentials(oauth_auth_json))
      assert_nil @adapter.token_expires_at({ "auth" => { "s" => { "key" => "k", "expires_at" => "whenever" } } })
      assert_nil @adapter.token_expires_at({})
      assert_nil @adapter.token_expires_at(nil)
    end

    # == MCP ==

    test "mcp_config emits a TOML table per server, keyed by transport" do
      servers = [
        OpenStruct.new(name: "aixle-tools", transport: "http", url: "https://mcp.example/mcp",
                       headers: { "Authorization" => "Bearer secret" }),
        OpenStruct.new(name: "playwright", transport: "stdio", command: "npx",
                       args: [ "@playwright/mcp@latest", "--headless" ])
      ]

      toml = @adapter.mcp_config(servers)["/home/grok/.grok/config.toml"]

      assert_match(/\[mcp_servers\."aixle-tools"\]/, toml)
      assert_match(%r{url = "https://mcp\.example/mcp"}, toml)
      assert_match(/headers = \{ "Authorization" = "Bearer secret" \}/, toml)
      assert_match(/\[mcp_servers\."playwright"\]/, toml)
      assert_match(/command = "npx"/, toml)
      assert_equal :append_toml, @adapter.mcp_merge_strategy
    end

    test "mcp_config pins the Playwright MCP command to the baked version (task #340)" do
      servers = [
        OpenStruct.new(name: "playwright", transport: "stdio",
                       command: "npx", args: [ "@playwright/mcp@latest", "--headless" ])
      ]

      toml = @adapter.mcp_config(servers)["/home/grok/.grok/config.toml"]

      assert_match(/args = \["@playwright\/mcp@#{Regexp.escape(BaseAdapter::PLAYWRIGHT_MCP_VERSION)}", "--headless"\]/, toml)
      refute_match(/@playwright\/mcp@latest/, toml)
      assert_match(/"PLAYWRIGHT_BROWSERS_PATH" = "\/opt\/playwright-browsers"/, toml)
    end

    # The table key is the same protocol key every other runtime writes, so a server's
    # tool namespace does not change with the runtime.
    test "mcp_config keys tables by the shared MCP protocol key" do
      servers = [ OpenStruct.new(name: "Aixle Tools", transport: "http", url: "https://x/mcp", headers: {}) ]

      toml = @adapter.mcp_config(servers)["/home/grok/.grok/config.toml"]

      assert_match(/\[mcp_servers\."aixle_tools"\]/, toml)
    end

    # A quote or backslash in a header value must not break out of the TOML string.
    test "mcp_config escapes TOML string values" do
      servers = [ OpenStruct.new(name: "tavily", transport: "http", url: "https://x/mcp",
                                 headers: { 'X-Ta"g' => 'a\\b"c' }) ]

      toml = @adapter.mcp_config(servers)["/home/grok/.grok/config.toml"]

      assert_includes toml, 'headers = { "X-Ta\\"g" = "a\\\\b\\"c" }'
    end

    # == Models ==

    test "fetch_available_models maps the xAI catalogue into picker entries" do
      stub_request(:get, GrokAdapter::MODELS_URL)
        .with(headers: { "Authorization" => "Bearer xai-test-key" })
        .to_return(
          status: 200,
          body: {
            models: [
              { id: "grok-4.5", input_modalities: %w[text image], max_prompt_length: 500_000 },
              { id: "grok-code-fast-1", input_modalities: %w[text], max_prompt_length: 256_000 }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = @adapter.fetch_available_models_with_source(@adapter.extract_credentials(api_key_auth_json))

      assert_equal :api, result[:source]
      assert_equal %w[grok-4.5 grok-code-fast-1], result[:models].map { |m| m[:model_id] }
      assert_equal "input: text, image · context: 500000 tokens", result[:models].first[:description]
    end

    test "fetch_available_models authenticates with the session token when there is no API key" do
      stub = stub_request(:get, GrokAdapter::MODELS_URL)
             .with(headers: { "Authorization" => "Bearer grok-session-token" })
             .to_return(status: 200, body: { models: [ { id: "grok-4.6" } ] }.to_json)

      models = @adapter.fetch_available_models(@adapter.extract_credentials(oauth_auth_json))

      assert_requested stub
      assert_equal [ "grok-4.6" ], models.map { |m| m[:model_id] }
    end

    test "fetch_available_models falls back to the pinned list when the catalogue is unavailable" do
      stub_request(:get, GrokAdapter::MODELS_URL).to_return(status: 401, body: "")

      result = @adapter.fetch_available_models_with_source(@adapter.extract_credentials(api_key_auth_json))

      assert_equal :fallback, result[:source]
      assert_equal GrokAdapter::FALLBACK_MODELS, result[:models]
    end

    test "fetch_available_models falls back without calling out when there is no credential" do
      assert_equal GrokAdapter::FALLBACK_MODELS, @adapter.fetch_available_models({})
    end

    # == Usage ==

    def mitm_line(body, host: "api.x.ai", direction: "response", ts: "2026-08-14T12:00:00.000000Z")
      { _source: "http2-logger", direction: direction, host: host, path: "/v1/chat/completions",
        status_code: 200, ts: ts, body: body }.to_json
    end

    def chat_completion_body(model: "grok-4.5", prompt: 1_000, completion: 200, cached: 400, reasoning: 50)
      {
        model: model,
        usage: {
          prompt_tokens: prompt,
          completion_tokens: completion,
          total_tokens: prompt + completion,
          prompt_tokens_details: { cached_tokens: cached },
          completion_tokens_details: { reasoning_tokens: reasoning }
        }
      }.to_json
    end

    test "collect_usage records the token breakdown from the MITM log" do
      stub_request(:get, GrokAdapter::MODELS_URL).to_return(status: 401, body: "")

      @adapter.collect_usage(@session, { "logs/http.log" => "#{mitm_line(chat_completion_body)}\n" })

      stat = @session.reload.usage_statistic
      assert_equal 1_000, stat.input_tokens
      assert_equal 200, stat.output_tokens
      assert_equal 400, stat.cache_read_tokens
      assert_equal 0, stat.cache_write_tokens
      assert_equal [ "grok-4.5" ], stat.models
      assert_equal "mitm", stat.source
      assert_equal 1, stat.events_count
      assert_equal 50, stat.events_data.first.dig("tokenUsage", "reasoningTokens")
    end

    # The Responses API reports the same counts under different names; a build that
    # speaks it must not silently record zero usage.
    test "collect_usage understands the Responses API field names too" do
      stub_request(:get, GrokAdapter::MODELS_URL).to_return(status: 401, body: "")
      body = { model: "grok-4.6", usage: { input_tokens: 12, output_tokens: 7, total_tokens: 19 } }.to_json

      @adapter.collect_usage(@session, { "logs/http.log" => "#{mitm_line(body)}\n" })

      stat = @session.reload.usage_statistic
      assert_equal 12, stat.input_tokens
      assert_equal 7, stat.output_tokens
    end

    test "collect_usage skips request entries and other hosts" do
      log = [
        mitm_line(chat_completion_body, direction: "request"),
        mitm_line(chat_completion_body(prompt: 999), host: "api.openai.com"),
        "not json",
        mitm_line({ model: "grok-4.5", choices: [] }.to_json)
      ].join("\n")

      @adapter.collect_usage(@session, { "logs/http.log" => log })

      assert_nil @session.reload.usage_statistic
    end

    test "collect_usage records nothing when there is no MITM log" do
      @adapter.collect_usage(@session, {})

      assert_nil @session.reload.usage_statistic
    end

    # xAI quotes per-token prices in cents per 10^8 tokens, priced separately for
    # uncached input, cached input, and output.
    test "collect_usage prices usage from the xAI catalogue" do
      stub_request(:get, GrokAdapter::MODELS_URL).to_return(
        status: 200,
        body: {
          models: [ {
            id: "grok-build-0.1",
            aliases: [ "grok-code-fast-1" ],
            prompt_text_token_price: 10_000,
            cached_prompt_text_token_price: 2_000,
            completion_text_token_price: 20_000
          } ]
        }.to_json
      )
      create(:agent_credential, user: @user, company: @company, agent_type: "grok",
                                config_data: { "api_key" => "xai-test-key" })

      log = mitm_line(chat_completion_body(model: "grok-code-fast-1", prompt: 1_000_000,
                                           completion: 100_000, cached: 200_000, reasoning: 0))
      @adapter.collect_usage(@session, { "logs/http.log" => "#{log}\n" })

      # 800_000 uncached * 10_000 + 200_000 cached * 2_000 + 100_000 output * 20_000, / 1e8
      expected_cents = ((800_000 * 10_000) + (200_000 * 2_000) + (100_000 * 20_000)) / 100_000_000.0
      stat = @session.reload.usage_statistic
      assert_equal BigDecimal(expected_cents.to_s), stat.total_cents_precise
      assert_equal expected_cents.ceil, stat.cost_cents
    end

    test "collect_usage still records tokens when the price sheet is unavailable" do
      stub_request(:get, GrokAdapter::MODELS_URL).to_return(status: 500, body: "")

      @adapter.collect_usage(@session, { "logs/http.log" => "#{mitm_line(chat_completion_body)}\n" })

      stat = @session.reload.usage_statistic
      assert_equal 1_000, stat.input_tokens
      assert_equal 0, stat.cost_cents
    end

    # == Misc contract ==

    test "default_config_paths surfaces the paths the UI hints at" do
      assert_equal [ "~/.grok/config.toml", "AGENTS.md" ], GrokAdapter.default_config_paths
    end

    test "no extra env fields are required before the auth container starts" do
      assert_equal [], @adapter.required_env_fields
      refute @adapter.requires_env_fields?
      assert_equal({}, @adapter.env_vars_from_metadata({ "anything" => "here" }))
    end
  end
end
