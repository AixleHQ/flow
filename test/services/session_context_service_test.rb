# frozen_string_literal: true

require "test_helper"

class SessionContextServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:debug)

    # Reset cached runtime between tests (runtime now uses Thread.current)
    Thread.current[:session_context_runtime] = nil

    @default_runtime_mock = mock("default_runtime")
    @default_runtime_mock.stubs(:write_file).returns(true)
    @default_runtime_mock.stubs(:exec).returns([ [], [], 0 ])
    @default_runtime_mock.stubs(:read_file).returns(nil)
    ContainerRuntime.stubs(:build).returns(@default_runtime_mock)
  end

  teardown do
    Thread.current[:session_context_runtime] = nil
    cleanup_runtime_overrides
  end

  # ====================================================================
  # Story 9.2: inject_config_files
  # ====================================================================

  test "inject_config_files writes files to container with expanded paths" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {
      "config_files" => {
        "~/.claude/settings.json" => '{"permissions":{}}',
        "CLAUDE.md" => "# Context"
      }
    })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    written = {}
    runtime_mock.stubs(:write_file).with { |ctr, path, content, **| written[path] = { ctr: ctr, content: content }; true }.returns(true)

    SessionContextService.inject_config_files("abc123", session)

    assert_equal "abc123", written["/home/claude/.claude/settings.json"][:ctr]
    assert_equal '{"permissions":{}}', written["/home/claude/.claude/settings.json"][:content]
    assert_equal "# Context", written["CLAUDE.md"][:content]
  end

  test "inject_config_files skips when config_files is empty" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {})

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.expects(:write_file).never

    SessionContextService.inject_config_files("abc123", session)
  end

  test "inject_config_files skips when config_files is nil" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {
      "config_files" => nil
    })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.expects(:write_file).never

    SessionContextService.inject_config_files("abc123", session)
  end

  # ====================================================================
  # Story 9.4: generate_mcp_config
  # ====================================================================

  test "generate_mcp_config generates Claude Code format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    assert result.key?("/workspace/.mcp.json")
    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "sse", config["mcpServers"]["tavily"]["type"]
    assert_equal "https://tavily.com/mcp", config["mcpServers"]["tavily"]["url"]
  end

  # The adapters never see an MCPServer record — they are handed the resolved
  # OpenStruct — so this is the seam where a catalog install's argv can go missing.
  # It did: `command` alone was shell-split, which for a package connector holds the
  # runtime and nothing else, and the emitted config launched a bare `npx`.
  test "generate_mcp_config keeps the argv of a stdio server installed from the catalog" do
    server = create(:mcp_server, :custom, :stdio_transport, name: "remote-fs", scope: @project,
                    command: "npx", args: [ "-y", "remote-filesystem-mcp-server@0.1.2" ],
                    env: { "FS_TOKEN" => "t" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    entry = JSON.parse(SessionContextService.generate_mcp_config(session)["/workspace/.mcp.json"])
              .dig("mcpServers", "remote-fs")

    assert_equal "stdio", entry["type"]
    assert_equal "npx", entry["command"]
    assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], entry["args"]
    assert_equal "t", entry["env"]["FS_TOKEN"]
  end

  test "generate_mcp_config splits the command line of a hand-written stdio server" do
    server = create(:mcp_server, :custom, :stdio_transport, name: "local-mcp", scope: @project,
                    command: "uvx local-mcp-server==1.4.0 --verbose")
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    entry = JSON.parse(SessionContextService.generate_mcp_config(session)["/workspace/.mcp.json"])
              .dig("mcpServers", "local-mcp")

    assert_equal "uvx", entry["command"]
    assert_equal [ "local-mcp-server==1.4.0", "--verbose" ], entry["args"]
  end

  test "generate_mcp_config generates Cursor CLI format" do
    server = create(:mcp_server, :custom, name: "context7", url: "https://context7.com/mcp",
                    transport: "sse", scope: @project, headers: { "Authorization" => "Bearer test" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    assert result.key?("/workspace/.cursor/mcp.json")
    config = JSON.parse(result["/workspace/.cursor/mcp.json"])
    assert_equal "https://context7.com/mcp", config["mcpServers"]["context7"]["url"]
    assert_equal "Bearer test", config["mcpServers"]["context7"]["headers"]["Authorization"]
  end

  test "generate_mcp_config generates Gemini CLI format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    settings_path = "/home/gemini/.gemini/settings.json"
    assert result.key?(settings_path)
    config = JSON.parse(result[settings_path])
    assert config["mcpServers"]["tavily"]["trust"]
    assert_equal "https://tavily.com/mcp", config["mcpServers"]["tavily"]["httpUrl"]
  end

  test "generate_mcp_config generates Codex TOML format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    toml_path = "/home/codex/.codex/config.toml"
    assert result.key?(toml_path)
    assert_includes result[toml_path], '[mcp_servers."tavily"]'
    assert_includes result[toml_path], 'url = "https://tavily.com/mcp"'
    refute_includes result[toml_path], 'type = "'
  end

  test "generate_mcp_config generates Grok TOML format with plain headers" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project,
                    headers: { "Authorization" => "Bearer secret123" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "grok")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    toml_path = "/home/grok/.grok/config.toml"
    assert result.key?(toml_path)
    assert_includes result[toml_path], '[mcp_servers."tavily"]'
    assert_includes result[toml_path], 'url = "https://tavily.com/mcp"'
    # Grok reads `headers`, not Codex's `http_headers`, and infers the transport
    # from url-vs-command — there is no type field.
    assert_includes result[toml_path], 'headers = { "Authorization" = "Bearer secret123" }'
    refute_includes result[toml_path], 'type = "'
  end

  test "inject_mcp_config appends Grok TOML to the generated config" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "grok")
    session.mcp_servers << server

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    existing_toml = "[ui]\npermission_mode = \"always-approve\"\n"
    runtime_mock.expects(:read_file).with("abc123", "/home/grok/.grok/config.toml").returns(existing_toml)

    runtime_mock.expects(:write_file).with do |ctr, path, content|
      ctr == "abc123" && path == "/home/grok/.grok/config.toml" &&
        content.include?("permission_mode") && content.include?('[mcp_servers."tavily"]')
    end.returns(true)

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "generate_mcp_config Codex uses http_headers not headers" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project,
                    headers: { "Authorization" => "Bearer secret123" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    toml_path = "/home/codex/.codex/config.toml"
    assert_includes result[toml_path], 'http_headers = { "Authorization" = "Bearer secret123" }'
    refute_includes result[toml_path], "\nheaders = "
  end

  test "generate_mcp_config resolves secrets in headers" do
    create(:config_item, name: "TAVILY_API_KEY", value: "tvly-secret", item_type: :variable, scope: @project)
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project,
                    headers: { "Authorization" => "Bearer config_item:TAVILY_API_KEY" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "Bearer tvly-secret", config["mcpServers"]["tavily"]["headers"]["Authorization"]
  end

  # A value that reaches the container through an MCP header is handed out as
  # surely as one fetched with get_config_item: audited, and armed for the
  # container's log filters before the file carrying it is written.
  test "inject_mcp_config audits each referenced value and arms redaction before writing the config" do
    item = create(:config_item, name: "TAVILY_API_KEY", value: "tvly-secret", item_type: :secret, scope: @project)
    create(:config_item, name: "UNRELATED_KEY", value: "not-sent", item_type: :secret, scope: @project)
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp", transport: "sse",
                                          scope: @project, headers: { "Authorization" => "Bearer config_item:TAVILY_API_KEY" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    writes = []
    @default_runtime_mock.stubs(:write_file).with { |_ctr, path, content, **| writes << [ path, content ]; true }.returns(true)

    SessionContextService.inject_mcp_config("ctr-1", session)

    access = ConfigItemAccess.find_by!(terminal_session: session)
    assert_equal [ item.id, "mcp_config", "secret" ], [ access.config_item_id, access.channel, access.item_type ]
    assert_equal 1, ConfigItemAccess.where(terminal_session: session).count

    paths = writes.map(&:first)
    registry = paths.index(Sessions::SecretRegistry::LIST_PATH)
    config = paths.index("/workspace/.mcp.json")
    assert registry && config && registry < config, "redaction list must be written before the MCP config: #{paths.inspect}"
    assert_equal [ "tvly-secret" ], writes[registry].last.split("\n").map { |line| Base64.strict_decode64(line) }
  end

  test "inject_mcp_config writes no access row when no value is referenced" do
    server = create(:mcp_server, :custom, name: "plain", url: "https://plain.example.com/mcp", transport: "sse",
                                          scope: @project, headers: { "Authorization" => "Bearer literal-token" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    SessionContextService.inject_mcp_config("ctr-1", session)

    assert_not ConfigItemAccess.exists?(terminal_session: session)
  end

  test "a reference to another project's item stays unresolved" do
    other = create(:project, company: @company, owner: @user)
    create(:config_item, name: "OTHER_KEY", value: "other-project-secret", item_type: :secret, scope: other)
    server = create(:mcp_server, :custom, name: "probe", url: "https://probe.example.com/mcp", transport: "sse",
                                          scope: @project, headers: { "Authorization" => "Bearer config_item:OTHER_KEY" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    config = JSON.parse(SessionContextService.generate_mcp_config(session)["/workspace/.mcp.json"])

    assert_equal "Bearer config_item:OTHER_KEY", config["mcpServers"]["probe"]["headers"]["Authorization"]
  end

  test "generate_mcp_config skips disabled servers" do
    enabled = create(:mcp_server, :custom, name: "enabled-server", url: "https://a.com/mcp",
                     transport: "sse", scope: @project, enabled: true)
    disabled = create(:mcp_server, :custom, name: "disabled-server", url: "https://b.com/mcp",
                      transport: "sse", scope: @project, enabled: false)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << [ enabled, disabled ]

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert config["mcpServers"].key?("enabled-server")
    assert_not config["mcpServers"].key?("disabled-server")
  end

  # The session validates attachments when it is created; this is the second
  # line: a row attached some other way still never reaches the container.
  test "generate_mcp_config skips an MCP server that belongs to another project" do
    other_company = create(:company)
    foreign_project = create(:project, company: other_company, owner: create(:user, company: other_company))
    foreign = create(:mcp_server, :custom, name: "foreign-server", url: "https://c.com/mcp",
                     transport: "sse", scope: foreign_project, headers: { "Authorization" => "Bearer theirs" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << foreign

    config = JSON.parse(SessionContextService.generate_mcp_config(session)["/workspace/.mcp.json"])

    assert_not config["mcpServers"].key?("foreign-server")
  end

  test "generate_mcp_config always includes internal aixle-tools" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert config["mcpServers"].key?("aixle-tools")
    assert_equal "http", config["mcpServers"]["aixle-tools"]["type"]
    assert_equal session.mcp_key, config["mcpServers"]["aixle-tools"]["headers"]["X-Session-Key"]
  end

  test "generate_mcp_config keeps aixle-tools when associated servers are missing from DB" do
    server = create(:mcp_server, :custom, name: "real", url: "https://a.com/mcp",
                    transport: "sse", scope: @project)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal 2, config["mcpServers"].size
    assert config["mcpServers"].key?("aixle-tools")
    assert config["mcpServers"].key?("real")
  end

  # ====================================================================
  # Story 9.4: inject_mcp_config (container interaction)
  # ====================================================================

  test "inject_mcp_config writes Claude MCP file to container" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    runtime_mock.expects(:write_file).with do |ctr, path, content|
      ctr == "abc123" && path == "/workspace/.mcp.json" &&
        JSON.parse(content)["mcpServers"]["tavily"].present?
    end.returns(true)

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "inject_mcp_config merges Gemini settings" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli")
    session.mcp_servers << server

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    # read_file returns existing settings
    existing_settings = { "security" => { "auth" => { "selectedType" => "oauth-personal" } } }
    runtime_mock.expects(:read_file).with("abc123", "/home/gemini/.gemini/settings.json").returns(existing_settings.to_json)

    # Write merged settings
    runtime_mock.expects(:write_file).with do |ctr, path, content|
      next false unless ctr == "abc123" && path == "/home/gemini/.gemini/settings.json"

      parsed = JSON.parse(content)
      parsed["security"].present? && parsed["mcpServers"]["tavily"].present?
    rescue JSON::ParserError
      false
    end.returns(true)

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "inject_mcp_config appends Codex TOML" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @project, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")
    session.mcp_servers << server

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    # read_file returns existing config.toml
    existing_toml = "approval_policy = \"never\"\n"
    runtime_mock.expects(:read_file).with("abc123", "/home/codex/.codex/config.toml").returns(existing_toml)

    # Write appended config
    runtime_mock.expects(:write_file).with do |ctr, path, content|
      ctr == "abc123" && path == "/home/codex/.codex/config.toml" &&
        content.include?("approval_policy") && content.include?('[mcp_servers."tavily"]')
    end.returns(true)

    SessionContextService.inject_mcp_config("abc123", session)
  end

  # The Codex append is a read-modify-write over the same config.toml the credential
  # step already wrote, and that file carries the trusted-project entry. Overwriting
  # it with the MCP block alone leaves a file that still parses and trusts nothing, so
  # the CLI starts and asks "Do you trust the contents of this directory?" — which a
  # non_interactive workflow step can never answer (task #605).
  test "inject_mcp_config keeps an unreadable config.toml instead of overwriting it" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")

    fake = stub_container_runtime(agent_type: "codex")
    Thread.current[:session_context_runtime] = nil
    toml_path = "/home/codex/.codex/config.toml"
    credential_config = "approval_policy = \"never\"\n\n[projects.\"/workspace\"]\ntrust_level = \"trusted\"\n"
    fake.fs[toml_path] = credential_config
    fake.fail_read(toml_path)

    SessionContextService.inject_mcp_config("abc123", session)

    assert_equal credential_config, fake.fs[toml_path]
  end

  # The failure that swallows the read is the one likeliest to swallow the existence
  # probe as well, so the probe must not answer "absent" when it could not answer at
  # all: an unreadable file plus an unanswerable probe still has to leave the file
  # alone rather than replace it with the MCP block.
  test "inject_mcp_config keeps a config.toml it could neither read nor probe" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")

    fake = stub_container_runtime(agent_type: "codex")
    Thread.current[:session_context_runtime] = nil
    toml_path = "/home/codex/.codex/config.toml"
    credential_config = "approval_policy = \"never\"\n\n[projects.\"/workspace\"]\ntrust_level = \"trusted\"\n"
    fake.fs[toml_path] = credential_config
    fake.fail_read(toml_path)
    fake.raise_on_exec("test -f", error: ContainerRuntime::ContainerUnreachableError.new(container_identifier: "abc123"))

    SessionContextService.inject_mcp_config("abc123", session)

    assert_equal credential_config, fake.fs[toml_path]
  end

  test "inject_mcp_config writes a fresh config.toml when there is none to append to" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex")

    fake = stub_container_runtime(agent_type: "codex")
    Thread.current[:session_context_runtime] = nil
    toml_path = "/home/codex/.codex/config.toml"

    SessionContextService.inject_mcp_config("abc123", session)

    assert_includes fake.fs[toml_path], "[mcp_servers."
  end

  test "inject_mcp_config writes aixle-tools even without external mcp servers" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    runtime_mock.expects(:write_file).with do |ctr, path, content|
      ctr == "abc123" && path == "/workspace/.mcp.json" &&
        JSON.parse(content).dig("mcpServers", "aixle-tools").present?
    end.returns(true)

    SessionContextService.inject_mcp_config("abc123", session)
  end

  # ====================================================================
  # Story 9.6: inject_skills (via npx skills add)
  # ====================================================================

  test "inject_skills skips when no skills associated" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code")

    result = SessionContextService.inject_skills("ctr1", session)
    assert_equal({}, result)
  end

  # Every `skills add` otherwise POSTs an install event upstream (source, skill
  # slugs, agent, and the path each skill landed at), which publishes what sessions
  # here install and inflates the leaderboard the catalog is ranked by.
  test "inject_skills disables skills.sh telemetry" do
    skill = create(:skill, scope: @project, name: "mantine-form",
                   source: "mantinedev/skills", package: "mantinedev/skills@mantine-form")
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.skills << skill

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    runtime_mock.expects(:exec).with do |ctr, cmd, _opts|
      ctr == "abc123" &&
        cmd.first(2) == [ "env", "DISABLE_TELEMETRY=1" ] &&
        # The slug as upstream published it, taken from `package` — `name` is
        # downcased by the model and `--skill` matches upstream's own directory.
        cmd[cmd.index("--skill") + 1] == "mantine-form"
    end.returns([ [], [], 0 ])

    result = SessionContextService.inject_skills("abc123", session)

    assert_equal "ok", result["mantinedev/skills@mantine-form"]
  end

  # A hand-written skill goes nowhere near the CLI, so no install event about it
  # ever leaves this deployment.
  test "inject_skills writes manual skills into the container without invoking the CLI" do
    skill = create(:skill, scope: @project, origin: :manual, name: "house-style",
                   source: nil, package: nil, content: "---\nname: house-style\n---\n\n# House style\n")
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.skills << skill

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    # The path is the one `skills add -g -a claude-code` would have used, the
    # directory name equals the skill name as the Agent Skills spec requires, and it
    # is written with the agent's uid — writing as root would leave ~/.claude owned by
    # root and every later agent write would fail with EACCES.
    runtime_mock.expects(:write_file)
                .with("abc123", "/home/claude/.claude/skills/house-style/SKILL.md", skill.content,
                      uid: 1001, gid: 1001)
                .returns(true)
    runtime_mock.expects(:exec).never

    result = SessionContextService.inject_skills("abc123", session)

    assert_equal "ok", result["house-style"]
  end

  # The release a person installed is what runs: nothing is fetched from upstream
  # at session start, so a change upstream reaches no session until someone installs
  # it again.
  test "inject_skills writes a registry skill's stored files instead of fetching upstream" do
    skill = create(:skill, scope: @project, name: "pdf", source: "anthropics/skills", package: "anthropics/skills@pdf",
                           files: { "SKILL.md" => "---\nname: pdf\n---\n", "scripts/fill.py" => "print(1)" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.skills << skill

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.expects(:write_file)
                .with("abc123", "/home/claude/.claude/skills/pdf/SKILL.md", "---\nname: pdf\n---\n", uid: 1001, gid: 1001)
                .returns(true)
    runtime_mock.expects(:write_file)
                .with("abc123", "/home/claude/.claude/skills/pdf/scripts/fill.py", "print(1)", uid: 1001, gid: 1001)
                .returns(true)
    runtime_mock.expects(:exec).never

    assert_equal "ok", SessionContextService.inject_skills("abc123", session)["anthropics/skills@pdf"]
  end

  test "inject_skills reports a failed manual write instead of raising" do
    skill = create(:skill, scope: @project, origin: :manual, name: "house-style",
                   source: nil, package: nil, content: "---\nname: house-style\n---\n\nbody\n")
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.skills << skill

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(false)

    result = SessionContextService.inject_skills("abc123", session)

    assert_match(/error/, result["house-style"])
  end

  # ====================================================================
  # Story 9.7: Adapter context_file_path
  # ====================================================================

  test "Claude adapter context_file_path returns home dir CLAUDE.md" do
    adapter = Agents::ClaudeCodeAdapter.new
    assert_equal "/home/claude/.claude/CLAUDE.md", adapter.context_file_path
  end

  test "Codex adapter context_file_path returns workspace AGENTS.md" do
    adapter = Agents::CodexAdapter.new
    assert_equal "/workspace/AGENTS.md", adapter.context_file_path
  end

  test "Gemini adapter context_file_path returns home dir GEMINI.md" do
    adapter = Agents::GeminiCliAdapter.new
    assert_equal "/home/gemini/.gemini/GEMINI.md", adapter.context_file_path
  end

  test "Cursor adapter context_file_path returns workspace AGENTS.md" do
    adapter = Agents::CursorCliAdapter.new
    assert_equal "/workspace/AGENTS.md", adapter.context_file_path
  end

  # A home-level rule file, not AGENTS.md: ~/.grok/rules/*.md is scanned on every
  # session in every directory, so /workspace stays clean.
  test "Grok adapter context_file_path returns a home dir rule file" do
    adapter = Agents::GrokAdapter.new
    assert_equal "/home/grok/.grok/rules/aixle-session-context.md", adapter.context_file_path
  end

  test "Base adapter context_file_path returns nil" do
    adapter = Agents::BaseAdapter.new
    assert_nil adapter.context_file_path
  end

  # ====================================================================
  # Story 25.7: Context is now generated via SessionContextConstructor
  # Legacy build_* private methods removed — tested in context_builders/
  # ====================================================================

  # ====================================================================
  # Story 25.7: inject_context_file (via SessionContextConstructor)
  # ====================================================================

  test "inject_context_file writes XML-tagged context to Claude CLAUDE.md" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    runtime_mock.expects(:write_file).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/claude/.claude/CLAUDE.md" &&
        content.include?("<session-context") &&
        content.include?("<workspace") &&
        content.include?("<shell-tools") &&
        content.include?("<output-rules")
    end.returns(true)

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file stores context_metadata on session" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec)

    SessionContextService.inject_context_file("ctr1", session)
    session.reload

    assert_not_nil session.context_metadata
    assert_equal session.id, session.context_metadata["session_id"]
    assert_kind_of Array, session.context_metadata["applied_builders"]
    assert_kind_of Array, session.context_metadata["sections"]
    assert_kind_of Numeric, session.context_metadata["build_time_ms"]
  end

  test "inject_context_file writes to correct path per agent type" do
    {
      "claude_code" => "/home/claude/.claude/CLAUDE.md",
      "codex" => "/workspace/AGENTS.md",
      "gemini_cli" => "/home/gemini/.gemini/GEMINI.md",
      "cursor_cli" => "/workspace/AGENTS.md",
      "grok" => "/home/grok/.grok/rules/aixle-session-context.md"
    }.each do |agent_type, expected_path|
      session = create(:terminal_session, user: @user, project: @project,
                       agent_type: agent_type, mode: "interactive")

      runtime_mock = mock("runtime_#{agent_type}")
      Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

      runtime_mock.expects(:write_file).with do |_ctr, path, _content|
        path == expected_path
      end.returns(true)

      SessionContextService.inject_context_file("ctr1", session)
    end
  end

  test "inject_context_file includes agent persona in XML output" do
    agent = Agent.create!(name: "reviewer", title: "Code Reviewer",
      persona: "You review code carefully.", scope: @project)
    session = create(:terminal_session, user: @user, project: @project,
      agent_type: "claude_code", mode: "interactive", configured_agent: agent)

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    runtime_mock.expects(:write_file).with do |_ctr, _path, content|
      content.include?("<agent-role") &&
        content.include?("Code Reviewer") &&
        content.include?("You review code carefully.")
    end.returns(true)

    SessionContextService.inject_context_file("ctr1", session)
  end

  # ====================================================================
  # Story 9.8: Adapter session_command
  # ====================================================================

  test "Claude adapter session_command returns claude for interactive mode" do
    adapter = Agents::ClaudeCodeAdapter.new
    assert_equal "claude", adapter.session_command(mode: "interactive")
  end

  test "Claude adapter session_command returns claude for non_interactive mode" do
    adapter = Agents::ClaudeCodeAdapter.new
    result = adapter.session_command(mode: "non_interactive")
    assert_equal "claude", result
  end

  test "Codex adapter session_command returns codex --yolo for interactive mode" do
    adapter = Agents::CodexAdapter.new
    assert_equal "codex --yolo -c projects./workspace.trust_level=trusted",
                 adapter.session_command(mode: "interactive")
  end

  test "Codex adapter session_command returns codex --yolo for non_interactive mode" do
    adapter = Agents::CodexAdapter.new
    result = adapter.session_command(mode: "non_interactive")
    assert_equal "codex --yolo -c projects./workspace.trust_level=trusted", result
  end

  test "Gemini adapter session_command returns gemini --yolo for interactive mode" do
    adapter = Agents::GeminiCliAdapter.new
    assert_equal "gemini --yolo", adapter.session_command(mode: "interactive")
  end

  test "Gemini adapter session_command returns yolo command for non_interactive mode" do
    adapter = Agents::GeminiCliAdapter.new
    result = adapter.session_command(mode: "non_interactive")
    assert_equal "gemini --yolo", result
  end

  test "Grok adapter session_command returns grok --yolo for both modes" do
    adapter = Agents::GrokAdapter.new
    assert_equal "grok --yolo", adapter.session_command(mode: "interactive")
    assert_equal "grok --yolo", adapter.session_command(mode: "non_interactive")
  end

  test "Cursor adapter session_command returns agent --force for interactive mode" do
    adapter = Agents::CursorCliAdapter.new
    assert_equal "agent --force", adapter.session_command(mode: "interactive")
  end

  test "Cursor adapter session_command returns agent --force for non_interactive mode" do
    adapter = Agents::CursorCliAdapter.new
    result = adapter.session_command(mode: "non_interactive")
    assert_equal "agent --force", result
  end

  test "Base adapter session_command raises NotImplementedError" do
    adapter = Agents::BaseAdapter.new
    assert_raises(NotImplementedError) do
      adapter.session_command(mode: "interactive")
    end
  end

  # ====================================================================
  # Story 9.8: assemble_session_context
  # ====================================================================

  test "assemble_session_context orchestrates all steps in order" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    credential_mock = mock("credential")
    credential_mock.stubs(:agent_type).returns("claude_code")
    credential_mock.stubs(:config_data).returns({ "oauthAccount" => {}, "primaryApiKey" => "sk-test" })
    credential_mock.stubs(:default_model).returns(nil)

    call_order = sequence("assembly_order")

    # Step 1: Credentials (with workflow_config for MCP pre-approval)
    credential_mock.expects(:write_to_container).with do |ctr, config|
      ctr == "ctr1" && config.is_a?(Hash) && config[:enabled_mcp_servers].is_a?(Array)
    end.in_sequence(call_order)

    # Step 2: Config files — no config_files in session_config, skipped internally

    # Step 3: MCP config — always includes aixle-tools
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/workspace/.mcp.json"
    end.returns(true).in_sequence(call_order)

    # Step 4: Skills — no skills, skipped internally

    # Step 5: Context file — writes XML-tagged content via Constructor
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/home/claude/.claude/CLAUDE.md"
    end.returns(true).in_sequence(call_order)

    # Step 8: Context log
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/var/log/context.log"
    end.returns(true).in_sequence(call_order)

    SessionContextService.assemble_session_context("ctr1", session, credential: credential_mock)
  end

  test "assemble_session_context redacts resolved secrets from context.log but keeps them in the container config" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    url: "https://mcp.example.com",
                    headers: { "Authorization" => "super-secret-token-value" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code", mode: "interactive")
    session.mcp_servers << server

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:read_file).returns(nil)

    captured = {}
    runtime_mock.stubs(:write_file).with do |_ctr, path, content|
      captured[path] = content
      true
    end.returns(true)

    SessionContextService.assemble_session_context("ctr1", session, credential: nil)

    mcp_config = captured["/workspace/.mcp.json"]
    context_log = captured["/var/log/context.log"]

    # The container's MCP config keeps the real secret — the agent needs it.
    assert_includes mcp_config, "super-secret-token-value"

    # context.log keeps the header KEY but scrubs the VALUE to a fingerprint.
    assert_includes context_log, "Authorization"
    assert_not_includes context_log, "super-secret-token-value"
    assert_match(/«redacted:sha256:[0-9a-f]{8}»/, context_log)

    # The internal aixle-tools X-Session-Key (session.mcp_key) is scrubbed too.
    assert_not_includes context_log, session.mcp_key if session.mcp_key.present?
  end

  test "assemble_session_context skips credentials when nil" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    # MCP config (aixle-tools)
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/workspace/.mcp.json"
    end.returns(true)

    # Context file — writes XML-tagged content via Constructor
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/home/claude/.claude/CLAUDE.md"
    end.returns(true)

    # Context log
    runtime_mock.expects(:write_file).with do |ctr, path, _content|
      ctr == "ctr1" && path == "/var/log/context.log"
    end.returns(true)

    result = SessionContextService.assemble_session_context("ctr1", session, credential: nil)
    assert_nil result
  end

  # AgentSessionStrategy#before_exec reads this return value directly (no block/yield)
  # to know how a launch-time credential preflight should log the write outcome.
  test "assemble_session_context returns the credential write result" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)

    credential_mock = mock("credential")
    credential_mock.stubs(:agent_type).returns("claude_code")
    credential_mock.stubs(:config_data).returns({ "oauthAccount" => {} })
    credential_mock.stubs(:default_model).returns(nil)
    credential_mock.expects(:write_to_container).returns(true)

    result = SessionContextService.assemble_session_context("ctr1", session, credential: credential_mock)
    assert result
  end

  test "assemble_session_context logs timing for each step" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     mode: "interactive")

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    # Allow all runtime calls
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:read_file).returns(nil)
    runtime_mock.stubs(:exec)

    # Unstub info to capture calls
    Rails.logger.unstub(:info)

    logged_messages = []
    Rails.logger.stubs(:info).with { |msg| logged_messages << msg; true }

    SessionContextService.assemble_session_context("ctr1", session)

    step_logs = logged_messages.select { |m| m.include?("[SessionContext] Step") }
    assert step_logs.any? { |m| m.include?("'config_files'") }
    assert step_logs.any? { |m| m.include?("'mcp_config'") }
    assert step_logs.any? { |m| m.include?("'skills'") }
    assert step_logs.any? { |m| m.include?("'context_file'") }
    assert logged_messages.any? { |m| m.include?("Assembly complete") }
  end

  # ====================================================================
  # Adapter: default_config_paths
  # ====================================================================

  test "Claude adapter has default_config_paths" do
    paths = Agents::ClaudeCodeAdapter.default_config_paths
    assert_includes paths, "~/.claude/settings.json"
    assert_includes paths, "CLAUDE.md"
  end

  test "Codex adapter has default_config_paths" do
    paths = Agents::CodexAdapter.default_config_paths
    assert_includes paths, "~/.codex/config.toml"
    assert_includes paths, "AGENTS.md"
  end

  test "Gemini adapter has default_config_paths" do
    paths = Agents::GeminiCliAdapter.default_config_paths
    assert_includes paths, "~/.gemini/settings.json"
    assert_includes paths, "GEMINI.md"
  end

  test "Cursor adapter has default_config_paths" do
    paths = Agents::CursorCliAdapter.default_config_paths
    assert_includes paths, "~/.cursor/cli-config.json"
    assert_includes paths, ".cursorrules"
  end

  test "Grok adapter has default_config_paths" do
    paths = Agents::GrokAdapter.default_config_paths
    assert_includes paths, "~/.grok/config.toml"
    assert_includes paths, "AGENTS.md"
  end

  test "Base adapter returns empty default_config_paths" do
    assert_equal [], Agents::BaseAdapter.default_config_paths
  end

  # ====================================================================
  # Story 14.3: inject_repositories
  # ====================================================================

  # The token authenticates the clone through a header read from a deleted 0600
  # file, and every later fetch/push goes through the helper: it is in no remote,
  # no argv and no exec command (the Kubernetes exec API logs its command).
  def github_session(*full_names)
    integration = create(:integration, company: @company, connected_by: @user, status: :active)
    repos = full_names.map do |full_name|
      create(:repository, full_name: full_name, source_branch: "main", integration: integration, scope: @project)
    end
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.repositories << repos
    [ session, repos ]
  end

  test "inject_repositories clones GitHub repositories without the token in any command or remote" do
    session, (repo, *) = github_session("acme/my-app")
    runtime = stub_container_runtime
    Thread.current[:session_context_runtime] = nil
    Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new(token: "ghs_test_token"))

    SessionContextService.send(:inject_repositories, "ctr1", session)

    commands = runtime.execs.map { |cmd| Array(cmd).join(" ") }
    clone = commands.find { |c| c.include?("clone") }
    assert_includes clone, "git --config-env=http.extraheader=AIXLE_GIT_AUTH_HEADER clone --depth=1 --branch=main " \
                           "https://github.com/acme/my-app.git /workspace/repo/my-app"
    assert_includes clone, "credential.https://github.com/acme/my-app.git.helper /workspace/.aixle/git-credential-aixle"
    assert_includes clone, "chown -R 1001:1001 /workspace/repo/my-app"
    assert commands.none? { |c| c.include?("ghs_test_token") }, "the token must never be part of a command"

    header_file = runtime.fs.keys.find { |path| path.start_with?("/tmp/.aixle-git-") }
    assert_equal 0o600, runtime.file_attributes(header_file)[:mode]
    assert_equal "Authorization: Basic #{Base64.strict_encode64('x-access-token:ghs_test_token')}", runtime.fs[header_file]
    assert runtime.fs["/workspace/.aixle/git-credential-aixle"].present?
    assert_not_nil repo.reload.last_fetched_at
  end

  test "inject_repositories mints a token narrowed to each repository" do
    session, = github_session("acme/app", "acme/infra")
    stub_container_runtime
    Thread.current[:session_context_runtime] = nil
    tokens = FakeGithub::TokenService.new(token: "ghs_scoped")
    Github::TokenService.stubs(:new).returns(tokens)

    SessionContextService.send(:inject_repositories, "ctr1", session)

    assert_equal [ [ "app" ], [ "infra" ] ], tokens.calls_to(:generate_installation_token).map { |call| call[:repositories] }
  end

  test "inject_repositories records a failing clone and still clones the others, retrying once" do
    session, (repo_bad, repo_ok) = github_session("acme/bad", "acme/good")
    runtime = stub_container_runtime
    Thread.current[:session_context_runtime] = nil
    SessionContextService.stubs(:sleep)
    Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new(token: "ghs_token"))
    runtime.fail_exec("acme/bad.git", stderr: "fatal: Authentication failed", exit_code: 128)

    SessionContextService.send(:inject_repositories, "ctr1", session)

    assert_equal 2, runtime.execs.count { |cmd| Array(cmd).join(" ").include?("clone --depth=1 --branch=main https://github.com/acme/bad.git") }
    failed = session.reload.metadata["failed_repos"]
    assert_equal [ repo_bad.id ], failed.map { |f| f["id"] }
    assert_match(/Authentication failed/, failed.first["error"])
    assert_not_nil repo_ok.reload.last_fetched_at
  end

  test "inject_repositories fails only the repository the installation cannot reach" do
    session, (repo_ok, _repo_bad) = github_session("acme/good", "acme/bad")
    stub_container_runtime
    Thread.current[:session_context_runtime] = nil
    Github::TokenService.stubs(:new).returns(FakeGithub::TokenService.new(token: "ghs_scoped", unreachable: [ "bad" ]))

    SessionContextService.send(:inject_repositories, "ctr1", session)

    assert_not_nil repo_ok.reload.last_fetched_at
    failed = session.reload.metadata["failed_repos"]
    assert_equal [ "acme/bad" ], failed.map { |f| f["full_name"] }
    assert_match(/Token generation failed/, failed.first["error"])
  end

  test "inject_repositories clones a self-managed GitLab repository from that GitLab's own host" do
    Settings.gitlab.stubs(:endpoint).returns("https://gitlab.example.com/api/v4")
    integration = create(:integration, company: @company, connected_by: @user, status: :active, provider: :gitlab)
    integration.update!(credentials_data: { "personal_access_token" => "glpat-secret" })
    repo = create(:repository, full_name: "team/service", source_branch: "main", integration: integration, scope: @project)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.repositories << repo
    runtime = stub_container_runtime
    Thread.current[:session_context_runtime] = nil

    SessionContextService.send(:inject_repositories, "ctr1", session)

    commands = runtime.execs.map { |cmd| Array(cmd).join(" ") }
    assert commands.any? { |c| c.include?("clone --depth=1 --branch=main https://gitlab.example.com/team/service.git") }
    assert commands.none? { |c| c.include?("gitlab.com") || c.include?("glpat-secret") }
  end

  test "inject_repositories clones a public repository anonymously" do
    repo = create(:repository, :public_source, full_name: "rails/rails", source_branch: "main",
                  clone_url: "https://github.com/rails/rails.git", scope: @project)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.repositories << repo

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)

    Github::TokenService.expects(:new).never

    runtime_mock.expects(:exec).with do |_ctr, cmd|
      cmd[2].include?("git clone --depth=1 --branch=main https://github.com/rails/rails.git /workspace/repo/rails") &&
        !cmd[2].include?("x-access-token")
    end.returns([ [], [], 0 ])

    SessionContextService.send(:inject_repositories, "ctr1", session)

    repo.reload
    assert_not_nil repo.last_fetched_at
    assert_nil session.reload.metadata["failed_repos"]
  end

  test "inject_repositories skips inactive integration" do
    integration = create(:integration, company: @company, connected_by: @user, status: :inactive)
    repo = create(:repository, full_name: "acme/repo", source_branch: "main",
                  integration: integration, scope: @project)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.repositories << repo

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.expects(:exec).never

    SessionContextService.send(:inject_repositories, "ctr1", session)

    session.reload
    assert_equal 1, session.metadata["failed_repos"].size
  end

  test "inject_repositories skips when no repositories associated" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code")

    result = SessionContextService.send(:inject_repositories, "ctr1", session)
    assert_nil result
  end

  # Story 14.3: build_repositories_section — removed, now in ContextBuilders::Resources

  # ====================================================================
  # HABTM repository association
  # ====================================================================

  test "terminal_session repository_ids returns associated repo ids" do
    integration = create(:integration, company: @company, connected_by: @user, status: :active)
    repo1 = create(:repository, full_name: "acme/a", source_branch: "main",
                   integration: integration, scope: @project)
    repo2 = create(:repository, full_name: "acme/b", source_branch: "main",
                   integration: integration, scope: @project)
    session = create(:terminal_session, user: @user, agent_type: "claude_code")
    session.repositories << [ repo1, repo2 ]

    assert_includes session.repository_ids, repo1.id
    assert_includes session.repository_ids, repo2.id
  end

  test "terminal_session repository_ids returns empty array when no repos" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code")
    assert_equal [], session.repository_ids
  end

  # Story 19.12: Tool Execution Modes — tested in ContextBuilders::Tools

  # ====================================================================
  # Story 33.6: BMAD Method injection in assemble_session_context
  # ====================================================================

  test "assemble_session_context calls BmadMethodInjector when bmad_enabled is true" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: { "bmad_enabled" => true })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    injector_mock = mock("bmad_injector")
    injector_mock.expects(:inject!).once
    BmadMethodInjector.expects(:new).with("ctr1", session, runtime: runtime_mock).returns(injector_mock)

    SessionContextService.assemble_session_context("ctr1", session)
  end

  test "assemble_session_context skips BmadMethodInjector when bmad_enabled is false" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: { "bmad_enabled" => false })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    BmadMethodInjector.expects(:new).never

    SessionContextService.assemble_session_context("ctr1", session)
  end

  test "assemble_session_context skips BmadMethodInjector when bmad_enabled is absent" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: {})

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    BmadMethodInjector.expects(:new).never

    SessionContextService.assemble_session_context("ctr1", session)
  end

  test "assemble_session_context measures bmad_method step timing" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: { "bmad_enabled" => true })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    injector_mock = mock("bmad_injector")
    injector_mock.stubs(:inject!)
    BmadMethodInjector.stubs(:new).returns(injector_mock)

    Rails.logger.unstub(:info)
    logged_messages = []
    Rails.logger.stubs(:info).with { |msg| logged_messages << msg; true }

    SessionContextService.assemble_session_context("ctr1", session)

    assert logged_messages.any? { |m| m.include?("[SessionContext] Step 'bmad_method'") },
      "Expected bmad_method step timing to be logged"
  end

  test "assemble_session_context runs bmad_method after repositories and before context_file" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: { "bmad_enabled" => true })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:write_file).returns(true)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    Rails.logger.unstub(:info)
    step_order = []
    Rails.logger.stubs(:info).with do |msg|
      if msg.include?("[SessionContext] Step '")
        step_name = msg.match(/Step '([\w]+)'/)[1]
        step_order << step_name
      end
      true
    end

    injector_mock = mock("bmad_injector")
    injector_mock.stubs(:inject!)
    BmadMethodInjector.stubs(:new).returns(injector_mock)

    SessionContextService.assemble_session_context("ctr1", session)

    repo_idx = step_order.index("repositories")
    bmad_idx = step_order.index("bmad_method")
    ctx_idx = step_order.index("context_file")

    assert_not_nil repo_idx, "repositories step should be logged"
    assert_not_nil bmad_idx, "bmad_method step should be logged"
    assert_not_nil ctx_idx, "context_file step should be logged"
    assert_operator bmad_idx, :>, repo_idx, "bmad_method should run after repositories"
    assert_operator bmad_idx, :<, ctx_idx, "bmad_method should run before context_file"
  end

  test "assemble_session_context records bmad_method in context_log" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     mode: "interactive", session_config: { "bmad_enabled" => true, "bmad_modules" => %w[bmm cis] })

    runtime_mock = mock("runtime")
    Thread.current[:session_context_runtime] = nil
    ContainerRuntime.stubs(:build).returns(runtime_mock)
    runtime_mock.stubs(:exec).returns([ [], [], 0 ])

    injector_mock = mock("bmad_injector")
    injector_mock.stubs(:inject!)
    BmadMethodInjector.stubs(:new).returns(injector_mock)

    context_log_content = nil
    runtime_mock.stubs(:write_file).with do |_ctr, path, content|
      context_log_content = content if path == "/var/log/context.log"
      true
    end.returns(true)

    SessionContextService.assemble_session_context("ctr1", session)

    assert_not_nil context_log_content, "Context log should be written"
    assert_includes context_log_content, "bmad_method"
    assert_includes context_log_content, "bmm"
    assert_includes context_log_content, "cis"
  end

  # ====================================================================
  # OAuth token injection (oauth-unification §4.4)
  # ====================================================================

  test "generate_mcp_config injects a Bearer header when a token resolves for the server" do
    server = create(:mcp_server, :custom, name: "oauth-srv", url: "https://oauth.example.com/mcp",
                    transport: "sse", scope: @project, headers: {}, auth_type: :oauth)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server
    Oauth::TokenService.stubs(:access_token_for).returns("resolved-token")

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "Bearer resolved-token", config["mcpServers"]["oauth-srv"]["headers"]["Authorization"]
  end

  test "generate_mcp_config does not inject for a non-oauth server" do
    server = create(:mcp_server, :custom, name: "plain-srv", url: "https://plain.example.com/mcp",
                    transport: "sse", scope: @project, headers: {}) # auth_type defaults to :none
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server
    # A non-oauth server never consults the token service (auth_type gate).
    Oauth::TokenService.expects(:access_token_for).never

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_not config["mcpServers"]["plain-srv"].fetch("headers", {}).key?("Authorization")
  end

  test "generate_mcp_config leaves headers untouched when no OAuth token resolves" do
    server = create(:mcp_server, :custom, name: "oauth-srv", url: "https://oauth.example.com/mcp",
                    transport: "sse", scope: @project, headers: {}, auth_type: :oauth)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server
    Oauth::TokenService.stubs(:access_token_for).returns(nil)

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_not config["mcpServers"]["oauth-srv"].fetch("headers", {}).key?("Authorization")
  end

  test "generate_mcp_config never overwrites an explicit Authorization header" do
    server = create(:mcp_server, :custom, name: "oauth-srv", url: "https://oauth.example.com/mcp",
                    transport: "sse", scope: @project, auth_type: :oauth,
                    headers: { "Authorization" => "Bearer preset" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server
    # Presence of an explicit header short-circuits before TokenService is consulted.
    Oauth::TokenService.expects(:access_token_for).never

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "Bearer preset", config["mcpServers"]["oauth-srv"]["headers"]["Authorization"]
  end

  test "generate_mcp_config propagates ReauthRequired so the session-start preflight can block launch" do
    server = create(:mcp_server, :custom, name: "oauth-srv", url: "https://oauth.example.com/mcp",
                    transport: "sse", scope: @project, headers: {}, auth_type: :oauth)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code")
    session.mcp_servers << server
    Oauth::TokenService.stubs(:access_token_for).raises(Oauth::ReauthRequired.new(nil))

    # Phase 3 no longer swallows here — a missing/dead per_user credential must trip
    # the session-start preflight rather than silently launch without a token.
    assert_raises(Oauth::ReauthRequired) do
      SessionContextService.generate_mcp_config(session)
    end
  end

  private

  # Build a tar stream containing a single file (mirrors ContainerRuntime.read_file input format)
  def build_tar_stream(path, content)
    io = StringIO.new
    writer = Gem::Package::TarWriter.new(io)
    normalized = path.to_s.sub(%r{\A/}, "")
    writer.add_file(normalized, 0o644) { |f| f.write(content) }
    writer.close
    io.string
  end
end
