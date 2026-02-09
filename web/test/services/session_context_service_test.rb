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

    # Reset cached runtime between tests
    SessionContextService.instance_variable_set(:@runtime, nil)
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

    container_mock = mock("container")
    Docker::Container.expects(:get).with("abc123").returns(container_mock).twice

    # For settings.json: mkdir + write + chown
    container_mock.expects(:exec).with([ "mkdir", "-p", "/home/claude/.claude" ])
    container_mock.expects(:exec).with { |args| args[0] == "sh" && args[2].include?("base64 -d > /home/claude/.claude/settings.json") }
    container_mock.expects(:exec).with([ "chown", "1001:1001", "/home/claude/.claude/settings.json" ])

    # For CLAUDE.md: mkdir + write + chown
    container_mock.expects(:exec).with([ "mkdir", "-p", "." ])
    container_mock.expects(:exec).with { |args| args[0] == "sh" && args[2].include?("base64 -d > CLAUDE.md") }
    container_mock.expects(:exec).with([ "chown", "1001:1001", "CLAUDE.md" ])

    SessionContextService.inject_config_files("abc123", session)
  end

  test "inject_config_files skips when config_files is empty" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {})

    Docker::Container.expects(:get).never

    SessionContextService.inject_config_files("abc123", session)
  end

  test "inject_config_files skips when config_files is nil" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {
      "config_files" => nil
    })

    Docker::Container.expects(:get).never

    SessionContextService.inject_config_files("abc123", session)
  end

  # ====================================================================
  # Story 9.3: resolve_env_vars
  # ====================================================================

  test "resolve_env_vars passes through direct values" do
    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "env_vars" => { "NODE_ENV" => "production", "WORKSPACE" => "/workspace" }
    })

    result = SessionContextService.resolve_env_vars(session)

    assert_equal "production", result["NODE_ENV"]
    assert_equal "/workspace", result["WORKSPACE"]
  end

  test "resolve_env_vars resolves config_item references" do
    create(:config_item, name: "ANTHROPIC_API_KEY", value: "sk-ant-test-key", item_type: :variable, scope: @company)

    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "env_vars" => { "ANTHROPIC_API_KEY" => "config_item:ANTHROPIC_API_KEY" }
    })

    result = SessionContextService.resolve_env_vars(session)

    assert_equal "sk-ant-test-key", result["ANTHROPIC_API_KEY"]
  end

  test "resolve_env_vars skips missing config_item references" do
    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "env_vars" => {
        "MISSING_KEY" => "config_item:NONEXISTENT",
        "NODE_ENV" => "production"
      }
    })

    result = SessionContextService.resolve_env_vars(session)

    assert_nil result["MISSING_KEY"]
    assert_equal "production", result["NODE_ENV"]
  end

  test "resolve_env_vars returns empty hash when env_vars is empty" do
    session = create(:terminal_session, user: @user, session_config: {})

    result = SessionContextService.resolve_env_vars(session)

    assert_equal({}, result)
  end

  test "resolve_env_vars handles mixed direct and config_item values" do
    create(:config_item, name: "SECRET_KEY", value: "secret-value", item_type: :variable, scope: @project)

    session = create(:terminal_session, user: @user, project: @project, session_config: {
      "env_vars" => {
        "SECRET_KEY" => "config_item:SECRET_KEY",
        "PLAIN_VALUE" => "hello"
      }
    })

    result = SessionContextService.resolve_env_vars(session)

    assert_equal "secret-value", result["SECRET_KEY"]
    assert_equal "hello", result["PLAIN_VALUE"]
  end

  test "resolve_env_vars works without project (no config_items available)" do
    session = create(:terminal_session, user: @user, project: nil, session_config: {
      "env_vars" => {
        "SOME_REF" => "config_item:MISSING",
        "DIRECT" => "value"
      }
    })

    result = SessionContextService.resolve_env_vars(session)

    assert_nil result["SOME_REF"]
    assert_equal "value", result["DIRECT"]
  end

  # ====================================================================
  # Story 9.4: generate_mcp_config
  # ====================================================================

  test "generate_mcp_config generates Claude Code format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.generate_mcp_config(session)

    assert result.key?("/workspace/.mcp.json")
    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "sse", config["mcpServers"]["tavily"]["type"]
    assert_equal "https://tavily.com/mcp", config["mcpServers"]["tavily"]["url"]
  end

  test "generate_mcp_config generates Cursor CLI format" do
    server = create(:mcp_server, :custom, name: "context7", url: "https://context7.com/mcp",
                    transport: "sse", scope: @company, headers: { "Authorization" => "Bearer test" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.generate_mcp_config(session)

    assert result.key?("/workspace/.cursor/mcp.json")
    config = JSON.parse(result["/workspace/.cursor/mcp.json"])
    assert_equal "https://context7.com/mcp", config["mcpServers"]["context7"]["url"]
    assert_equal "Bearer test", config["mcpServers"]["context7"]["headers"]["Authorization"]
  end

  test "generate_mcp_config generates Gemini CLI format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.generate_mcp_config(session)

    settings_path = "/home/gemini/.gemini/settings.json"
    assert result.key?(settings_path)
    config = JSON.parse(result[settings_path])
    assert config["mcpServers"]["tavily"]["trust"]
    assert_equal "https://tavily.com/mcp", config["mcpServers"]["tavily"]["httpUrl"]
  end

  test "generate_mcp_config generates Codex TOML format" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.generate_mcp_config(session)

    toml_path = "/home/codex/.codex/config.toml"
    assert result.key?(toml_path)
    assert_includes result[toml_path], '[mcp_servers."tavily"]'
    assert_includes result[toml_path], 'type = "http"'
    assert_includes result[toml_path], 'url = "https://tavily.com/mcp"'
  end

  test "generate_mcp_config resolves secrets in headers" do
    create(:config_item, name: "TAVILY_API_KEY", value: "tvly-secret", item_type: :variable, scope: @company)
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company,
                    headers: { "Authorization" => "Bearer config_item:TAVILY_API_KEY" })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal "Bearer tvly-secret", config["mcpServers"]["tavily"]["headers"]["Authorization"]
  end

  test "generate_mcp_config skips disabled servers" do
    enabled = create(:mcp_server, :custom, name: "enabled-server", url: "https://a.com/mcp",
                     transport: "sse", scope: @company, enabled: true)
    disabled = create(:mcp_server, :custom, name: "disabled-server", url: "https://b.com/mcp",
                      transport: "sse", scope: @company, enabled: false)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ enabled.id, disabled.id ] })

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert config["mcpServers"].key?("enabled-server")
    assert_not config["mcpServers"].key?("disabled-server")
  end

  test "generate_mcp_config always includes internal palad-tools" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert config["mcpServers"].key?("palad-tools")
    assert_equal "sse", config["mcpServers"]["palad-tools"]["type"]
    assert_equal session.mcp_key, config["mcpServers"]["palad-tools"]["headers"]["X-Session-Key"]
  end

  test "generate_mcp_config skips non-existent server IDs but keeps palad-tools" do
    server = create(:mcp_server, :custom, name: "real", url: "https://a.com/mcp",
                    transport: "sse", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id, 999_999 ] })

    result = SessionContextService.generate_mcp_config(session)

    config = JSON.parse(result["/workspace/.mcp.json"])
    assert_equal 2, config["mcpServers"].size
    assert config["mcpServers"].key?("palad-tools")
    assert config["mcpServers"].key?("real")
  end

  # ====================================================================
  # Story 9.4: inject_mcp_config (container interaction)
  # ====================================================================

  test "inject_mcp_config writes Claude MCP file to container" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    container_mock = mock("container")
    Docker::Container.expects(:get).with("abc123").returns(container_mock).at_least_once

    container_mock.expects(:exec).with([ "mkdir", "-p", "/workspace" ]).once
    container_mock.expects(:exec).with { |args| args[0] == "sh" && args[2].include?("/workspace/.mcp.json") }.once
    container_mock.expects(:exec).with([ "chown", "1001:1001", "/workspace/.mcp.json" ]).once

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "inject_mcp_config merges Gemini settings" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    container_mock = mock("container")
    Docker::Container.expects(:get).with("abc123").returns(container_mock).at_least_once

    # Read existing settings returns existing config
    existing_settings = { "security" => { "auth" => { "selectedType" => "oauth-personal" } } }
    container_mock.expects(:exec).with([ "cat", "/home/gemini/.gemini/settings.json" ])
                  .returns([ [ existing_settings.to_json ], [], 0 ])

    # Write merged settings
    container_mock.expects(:exec).with([ "mkdir", "-p", "/home/gemini/.gemini" ])
    container_mock.expects(:exec).with { |args|
      next false unless args[0] == "sh"
      decoded = Base64.decode64(args[2].match(/echo '(.+)'/)[1]) rescue nil
      next false unless decoded
      parsed = JSON.parse(decoded) rescue nil
      next false unless parsed
      # Verify merge: original key preserved + mcpServers added
      parsed["security"].present? && parsed["mcpServers"]["tavily"].present?
    }.returns([ [], [], 0 ])
    container_mock.expects(:exec).with([ "chown", "1001:1001", "/home/gemini/.gemini/settings.json" ])

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "inject_mcp_config appends Codex TOML" do
    server = create(:mcp_server, :custom, name: "tavily", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company, headers: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    container_mock = mock("container")
    Docker::Container.expects(:get).with("abc123").returns(container_mock).at_least_once

    # Read existing config.toml
    container_mock.expects(:exec).with([ "cat", "/home/codex/.codex/config.toml" ])
                  .returns([ [ "approval_policy = \"never\"\n" ], [], 0 ])

    # Write appended config
    container_mock.expects(:exec).with([ "mkdir", "-p", "/home/codex/.codex" ])
    container_mock.expects(:exec).with { |args|
      next false unless args[0] == "sh"
      decoded = Base64.decode64(args[2].match(/echo '(.+)'/)[1]) rescue nil
      next false unless decoded
      # Verify original content preserved + MCP appended
      decoded.include?("approval_policy") && decoded.include?('[mcp_servers."tavily"]')
    }.returns([ [], [], 0 ])
    container_mock.expects(:exec).with([ "chown", "1001:1001", "/home/codex/.codex/config.toml" ])

    SessionContextService.inject_mcp_config("abc123", session)
  end

  test "inject_mcp_config writes palad-tools even without external mcp_server_ids" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    container_mock = mock("container")
    Docker::Container.expects(:get).with("abc123").returns(container_mock).at_least_once

    container_mock.expects(:exec).with([ "mkdir", "-p", "/workspace" ])
    container_mock.expects(:exec).with { |args|
      next false unless args[0] == "sh"
      decoded = Base64.decode64(args[2].match(/echo '(.+)'/)[1]) rescue nil
      next false unless decoded
      parsed = JSON.parse(decoded) rescue nil
      parsed&.dig("mcpServers", "palad-tools").present?
    }.returns([ [], [], 0 ])
    container_mock.expects(:exec).with([ "chown", "1001:1001", "/workspace/.mcp.json" ])

    SessionContextService.inject_mcp_config("abc123", session)
  end

  # ====================================================================
  # Story 9.6: inject_skills
  # ====================================================================

  test "inject_skills writes Claude skill files to container" do
    skill = create(:skill, name: "deploy-guide", content: "# Deploy Guide\nSteps here", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "skill_ids" => [ skill.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_to).with("ctr1", "/home/claude/.claude/skills/deploy-guide.md", skill.content).returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/skills/deploy-guide.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills writes Codex skill files with YAML front matter" do
    skill = create(:skill, name: "test-runner", content: "# Test Runner\nRun tests", description: "Runs tests", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex",
                     session_config: { "skill_ids" => [ skill.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/codex/.codex/skills/test-runner/SKILL.md" &&
        content.include?("---\nname: test-runner\n") &&
        content.include?('"Runs tests"') &&
        content.include?("# Test Runner")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/codex/.codex/skills/test-runner/SKILL.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills appends Gemini skill sections to GEMINI.md" do
    skill = create(:skill, name: "coding-style", title: "Coding Style", content: "Use 2 spaces", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli",
                     session_config: { "skill_ids" => [ skill.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    # read existing GEMINI.md — returns nil (file doesn't exist)
    runtime_mock.expects(:copy_from).with("ctr1", "/home/gemini/.gemini/GEMINI.md").returns(nil)
    # write appended content
    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/gemini/.gemini/GEMINI.md" &&
        content.include?("## Skill: Coding Style") &&
        content.include?("Use 2 spaces")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/gemini/.gemini/GEMINI.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills appends to existing GEMINI.md content" do
    skill = create(:skill, name: "coding-style", title: "Coding Style", content: "Use 2 spaces", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli",
                     session_config: { "skill_ids" => [ skill.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    existing_content = "# Project Context\nExisting content"
    tar_stream = build_tar_stream("/home/gemini/.gemini/GEMINI.md", existing_content)
    runtime_mock.expects(:copy_from).with("ctr1", "/home/gemini/.gemini/GEMINI.md").returns(tar_stream)

    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/gemini/.gemini/GEMINI.md" &&
        content.start_with?("# Project Context\nExisting content") &&
        content.include?("## Skill: Coding Style")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/gemini/.gemini/GEMINI.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills writes Cursor skill files to container" do
    skill = create(:skill, name: "review-guide", content: "# Review Guide\nCheck these things", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     session_config: { "skill_ids" => [ skill.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_to).with("ctr1", "/home/cursor/.cursor/rules/review-guide.md", skill.content).returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/cursor/.cursor/rules/review-guide.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills writes multiple skill files" do
    skill1 = create(:skill, name: "skill-a", content: "Content A", scope: @company)
    skill2 = create(:skill, name: "skill-b", content: "Content B", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "skill_ids" => [ skill1.id, skill2.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_to).with("ctr1", "/home/claude/.claude/skills/skill-a.md", "Content A").returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/skills/skill-a.md" ])
    runtime_mock.expects(:copy_to).with("ctr1", "/home/claude/.claude/skills/skill-b.md", "Content B").returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/skills/skill-b.md" ])

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills skips when skill_ids is empty" do
    session = create(:terminal_session, user: @user, agent_type: "claude_code", session_config: {})

    # Should not write anything — returns early
    result = SessionContextService.inject_skills("ctr1", session)
    assert_nil result
  end

  test "inject_skills skips missing skill IDs with warning" do
    skill = create(:skill, name: "existing", content: "Content", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "skill_ids" => [ skill.id, 999_999 ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_to).with("ctr1", "/home/claude/.claude/skills/existing.md", "Content").returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/skills/existing.md" ])

    Rails.logger.expects(:warn).with { |msg| msg.include?("Skill 999999 not found") }

    SessionContextService.inject_skills("ctr1", session)
  end

  test "inject_skills skips skills with blank content" do
    skill = build(:skill, name: "empty-skill", content: "", scope: @company)
    skill.save(validate: false) # bypass content presence validation

    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "skill_ids" => [ skill.id ] })

    # skill_files returns empty hash for blank content → no writes
    result = SessionContextService.inject_skills("ctr1", session)
    assert_nil result
  end

  # ====================================================================
  # Story 9.6: Adapter skill_files
  # ====================================================================

  test "Claude adapter skill_files returns correct paths and content" do
    adapter = Agents::ClaudeCodeAdapter.new
    skills = [
      OpenStruct.new(name: "deploy", content: "# Deploy", title: "Deploy", description: "Deploy guide"),
      OpenStruct.new(name: "test", content: "# Test", title: "Test", description: "Test guide")
    ]

    result = adapter.skill_files(skills)

    assert_equal 2, result.size
    assert_equal "# Deploy", result["/home/claude/.claude/skills/deploy.md"]
    assert_equal "# Test", result["/home/claude/.claude/skills/test.md"]
  end

  test "Codex adapter skill_files includes YAML front matter" do
    adapter = Agents::CodexAdapter.new
    skills = [ OpenStruct.new(name: "lint", content: "# Lint rules", title: "Linter", description: "Lint description") ]

    result = adapter.skill_files(skills)

    assert_equal 1, result.size
    content = result["/home/codex/.codex/skills/lint/SKILL.md"]
    assert content.start_with?("---\n")
    assert_includes content, "name: lint"
    assert_includes content, '"Lint description"'
    assert_includes content, "# Lint rules"
  end

  test "Gemini adapter skill_files concatenates into single GEMINI.md" do
    adapter = Agents::GeminiCliAdapter.new
    skills = [
      OpenStruct.new(name: "a", content: "Content A", title: "Skill A", description: nil),
      OpenStruct.new(name: "b", content: "Content B", title: "Skill B", description: nil)
    ]

    result = adapter.skill_files(skills)

    assert_equal 1, result.size
    content = result["/home/gemini/.gemini/GEMINI.md"]
    assert_includes content, "## Skill: Skill A"
    assert_includes content, "Content A"
    assert_includes content, "## Skill: Skill B"
    assert_includes content, "Content B"
    assert_includes content, "---" # separator between skills
  end

  test "Gemini adapter skill_merge_strategy is append" do
    adapter = Agents::GeminiCliAdapter.new
    assert_equal :append, adapter.skill_merge_strategy
  end

  test "Cursor adapter skill_files returns correct paths" do
    adapter = Agents::CursorCliAdapter.new
    skills = [ OpenStruct.new(name: "review", content: "# Review", title: "Review", description: nil) ]

    result = adapter.skill_files(skills)

    assert_equal 1, result.size
    assert_equal "# Review", result["/home/cursor/.cursor/rules/review.md"]
  end

  test "Base adapter skill_files returns empty hash" do
    adapter = Agents::BaseAdapter.new
    assert_equal({}, adapter.skill_files([]))
  end

  test "Base adapter skill_merge_strategy is fresh" do
    adapter = Agents::BaseAdapter.new
    assert_equal :fresh, adapter.skill_merge_strategy
  end

  test "adapter skill_files skips skills with blank content" do
    adapter = Agents::ClaudeCodeAdapter.new
    skills = [
      OpenStruct.new(name: "has-content", content: "# Content", title: "T", description: nil),
      OpenStruct.new(name: "no-content", content: "", title: "T", description: nil),
      OpenStruct.new(name: "nil-content", content: nil, title: "T", description: nil)
    ]

    result = adapter.skill_files(skills)

    assert_equal 1, result.size
    assert result.key?("/home/claude/.claude/skills/has-content.md")
  end

  # ====================================================================
  # Story 9.7: Adapter context_file_path
  # ====================================================================

  test "Claude adapter context_file_path returns home dir CLAUDE.md" do
    adapter = Agents::ClaudeCodeAdapter.new
    assert_equal "/home/claude/.claude/CLAUDE.md", adapter.context_file_path
  end

  test "Codex adapter context_file_path returns home dir AGENTS.md" do
    adapter = Agents::CodexAdapter.new
    assert_equal "/home/codex/.codex/AGENTS.md", adapter.context_file_path
  end

  test "Gemini adapter context_file_path returns home dir GEMINI.md" do
    adapter = Agents::GeminiCliAdapter.new
    assert_equal "/home/gemini/.gemini/GEMINI.md", adapter.context_file_path
  end

  test "Cursor adapter context_file_path returns home dir .cursorrules" do
    adapter = Agents::CursorCliAdapter.new
    assert_equal "/home/cursor/.cursor/rules/.cursorrules", adapter.context_file_path
  end

  test "Base adapter context_file_path returns nil" do
    adapter = Agents::BaseAdapter.new
    assert_nil adapter.context_file_path
  end

  # ====================================================================
  # Story 9.7: build_context_content (private builders via send)
  # ====================================================================

  test "build_agent_persona returns agent system prompt" do
    agent = Agent.create!(
      name: "coder", title: "Expert Coder", persona: "You are an expert coder.",
      scope_type: "Company", scope_id: @company.id
    )
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "agent_id" => agent.id })

    result = SessionContextService.send(:build_agent_persona, session)

    assert_includes result, "# Expert Coder"
    assert_includes result, "You are an expert coder."
  end

  test "build_agent_persona returns empty string when agent_id is blank" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    result = SessionContextService.send(:build_agent_persona, session)

    assert_equal "", result
  end

  test "build_agent_persona returns empty string when agent not found" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "agent_id" => 999_999 })

    result = SessionContextService.send(:build_agent_persona, session)

    assert_equal "", result
  end

  test "build_mcp_descriptions always includes palad-tools" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    result = SessionContextService.send(:build_mcp_descriptions, session)

    assert_includes result, "## Available MCP Servers"
    assert_includes result, "### palad-tools"
    assert_includes result, "Internal tools server"
  end

  test "build_mcp_descriptions includes external MCP servers" do
    server = create(:mcp_server, :custom, name: "tavily", display_name: "Tavily Search",
                    description: "Web search API", url: "https://tavily.com/mcp",
                    transport: "sse", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    result = SessionContextService.send(:build_mcp_descriptions, session)

    assert_includes result, "### palad-tools"
    assert_includes result, "### tavily"
    assert_includes result, "Tavily Search"
    assert_includes result, "Web search API"
  end

  test "build_mcp_descriptions skips disabled MCP servers" do
    enabled = create(:mcp_server, :custom, name: "enabled-srv", display_name: "Enabled",
                     url: "https://a.com/mcp", scope: @company, enabled: true)
    disabled = create(:mcp_server, :custom, name: "disabled-srv", display_name: "Disabled",
                      url: "https://b.com/mcp", scope: @company, enabled: false)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ enabled.id, disabled.id ] })

    result = SessionContextService.send(:build_mcp_descriptions, session)

    assert_includes result, "### enabled-srv"
    assert_not_includes result, "### disabled-srv"
  end

  test "build_tool_descriptions formats tool info with input schema" do
    tool = create(:tool, name: "web_search", display_name: "Web Search",
                  description: "Search the web", scope: @company,
                  input_schema: { "properties" => { "query" => { "type" => "string" }, "max_results" => { "type" => "integer" } } })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "tool_ids" => [ tool.id ] })

    result = SessionContextService.send(:build_tool_descriptions, session)

    assert_includes result, "## Available Tools"
    assert_includes result, "### web_search"
    assert_includes result, "Web Search"
    assert_includes result, "Search the web"
    assert_includes result, "Parameters: query (string), max_results (integer)"
  end

  test "build_tool_descriptions returns empty string when no tools" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    result = SessionContextService.send(:build_tool_descriptions, session)

    assert_equal "", result
  end

  test "build_context_content combines persona, MCP, and tools" do
    agent = Agent.create!(
      name: "dev", title: "Developer", persona: "You are a developer.",
      scope_type: "Company", scope_id: @company.id
    )
    server = create(:mcp_server, :custom, name: "context7", display_name: "Context7",
                    description: "Docs search", url: "https://ctx7.com/mcp", scope: @company)
    tool = create(:tool, name: "gh_pr", display_name: "GitHub PR",
                  description: "Create PRs", scope: @company, input_schema: {})
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {
                       "agent_id" => agent.id,
                       "mcp_server_ids" => [ server.id ],
                       "tool_ids" => [ tool.id ]
                     })

    result = SessionContextService.send(:build_context_content, session)

    assert_includes result, "# Developer"
    assert_includes result, "## Available MCP Servers"
    assert_includes result, "### context7"
    assert_includes result, "## Available Tools"
    assert_includes result, "### gh_pr"
  end

  test "build_context_content returns empty when nothing to add" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    # Only palad-tools is always present, so MCP descriptions are never fully empty
    result = SessionContextService.send(:build_context_content, session)

    assert_includes result, "## Available MCP Servers"
    assert_includes result, "### palad-tools"
  end

  # ====================================================================
  # Story 9.7: inject_context_file (container interaction)
  # ====================================================================

  test "inject_context_file writes Claude context file to container" do
    server = create(:mcp_server, :custom, name: "tavily", display_name: "Tavily",
                    description: "Search API", url: "https://tavily.com/mcp", scope: @company)
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "mcp_server_ids" => [ server.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    # read existing CLAUDE.md — returns nil (no existing content)
    runtime_mock.expects(:copy_from).with("ctr1", "/home/claude/.claude/CLAUDE.md").returns(nil)
    # write context file (no separator since no existing content)
    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/claude/.claude/CLAUDE.md" &&
        content.include?("## Available MCP Servers") &&
        content.include?("### palad-tools") &&
        content.include?("### tavily") &&
        !content.start_with?("\n\n---")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/CLAUDE.md" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file appends to existing content with separator" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: {})

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    existing_content = "# Existing Config\nSome previous content"
    tar_stream = build_tar_stream("/home/claude/.claude/CLAUDE.md", existing_content)
    runtime_mock.expects(:copy_from).with("ctr1", "/home/claude/.claude/CLAUDE.md").returns(tar_stream)

    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/claude/.claude/CLAUDE.md" &&
        content.start_with?("# Existing Config\nSome previous content") &&
        content.include?("\n\n---\n\n") &&
        content.include?("## Available MCP Servers")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/CLAUDE.md" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file writes Gemini context to GEMINI.md" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "gemini_cli",
                     session_config: {})

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_from).with("ctr1", "/home/gemini/.gemini/GEMINI.md").returns(nil)
    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/gemini/.gemini/GEMINI.md" &&
        content.include?("## Available MCP Servers") &&
        content.include?("### palad-tools")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/gemini/.gemini/GEMINI.md" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file writes Codex context to AGENTS.md" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "codex",
                     session_config: {})

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_from).with("ctr1", "/home/codex/.codex/AGENTS.md").returns(nil)
    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/codex/.codex/AGENTS.md" &&
        content.include?("## Available MCP Servers")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/codex/.codex/AGENTS.md" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file writes Cursor context to .cursorrules" do
    session = create(:terminal_session, user: @user, project: @project, agent_type: "cursor_cli",
                     session_config: {})

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_from).with("ctr1", "/home/cursor/.cursor/rules/.cursorrules").returns(nil)
    runtime_mock.expects(:copy_to).with do |ctr, path, content|
      ctr == "ctr1" &&
        path == "/home/cursor/.cursor/rules/.cursorrules" &&
        content.include?("## Available MCP Servers")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/cursor/.cursor/rules/.cursorrules" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file includes agent persona when configured" do
    agent = Agent.create!(
      name: "reviewer", title: "Code Reviewer", persona: "You review code carefully.",
      scope_type: "Company", scope_id: @company.id
    )
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "agent_id" => agent.id })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_from).with("ctr1", "/home/claude/.claude/CLAUDE.md").returns(nil)
    runtime_mock.expects(:copy_to).with do |_ctr, _path, content|
      content.include?("# Code Reviewer") &&
        content.include?("You review code carefully.") &&
        content.include?("## Available MCP Servers")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/CLAUDE.md" ])

    SessionContextService.inject_context_file("ctr1", session)
  end

  test "inject_context_file includes tool descriptions when tools configured" do
    tool = create(:tool, name: "deploy_tool", display_name: "Deploy",
                  description: "Deploy to production", scope: @company,
                  input_schema: { "properties" => { "env" => { "type" => "string" } } })
    session = create(:terminal_session, user: @user, project: @project, agent_type: "claude_code",
                     session_config: { "tool_ids" => [ tool.id ] })

    runtime_mock = mock("runtime")
    SessionContextService.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:copy_from).with("ctr1", "/home/claude/.claude/CLAUDE.md").returns(nil)
    runtime_mock.expects(:copy_to).with do |_ctr, _path, content|
      content.include?("## Available Tools") &&
        content.include?("### deploy_tool") &&
        content.include?("Deploy — Deploy to production") &&
        content.include?("Parameters: env (string)")
    end.returns(true)
    runtime_mock.expects(:exec).with("ctr1", [ "sh", "-c", "chown 1001:1001 /home/claude/.claude/CLAUDE.md" ])

    SessionContextService.inject_context_file("ctr1", session)
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

  test "Base adapter returns empty default_config_paths" do
    assert_equal [], Agents::BaseAdapter.default_config_paths
  end

  private

  # Build a tar stream containing a single file (mirrors ContainerRuntime.copy_from output)
  def build_tar_stream(path, content)
    io = StringIO.new
    writer = Gem::Package::TarWriter.new(io)
    normalized = path.to_s.sub(%r{\A/}, "")
    writer.add_file(normalized, 0o644) { |f| f.write(content) }
    writer.close
    io.string
  end
end
