# frozen_string_literal: true

require "test_helper"
require "shellwords"

# Story 35.4 — E2E Testing: BMAD on All Agent Runtimes
#
# Validates the full BMAD pipeline for each of the 4 agent runtimes:
#   session create → BmadMethodInjector.inject! → context assembly → filesystem verification
#
# Agent type → BMAD tool flag → skill directory mapping:
#   cursor_cli  → --tools cursor      → .cursor/skills/
#   claude_code → --tools claude-code  → .claude/skills/
#   codex       → --tools codex        → .agents/skills/
#   gemini_cli  → --tools gemini       → .gemini/skills/
class BmadE2eAllRuntimesTest < ActiveSupport::TestCase
  AGENT_RUNTIMES = {
    "cursor_cli" => {
      tool_flag: "cursor",
      skill_dir: "/home/cursor/.cursor/skills",
      context_path: "/workspace/AGENTS.md",
      home_dir: "/home/cursor"
    },
    "claude_code" => {
      tool_flag: "claude-code",
      skill_dir: "/home/claude/.claude/skills",
      context_path: "/home/claude/.claude/CLAUDE.md",
      home_dir: "/home/claude"
    },
    "codex" => {
      tool_flag: "codex",
      skill_dir: "/home/codex/.codex/skills",
      context_path: "/workspace/AGENTS.md",
      home_dir: "/home/codex"
    },
    "gemini_cli" => {
      tool_flag: "gemini",
      skill_dir: "/home/gemini/.gemini",
      context_path: "/home/gemini/.gemini/GEMINI.md",
      home_dir: "/home/gemini"
    }
  }.freeze

  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company,
                   preferred_agent_language: "es", name: "Maria Garcia")
    @project = create(:project, company: @company, owner: @user)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)
    Rails.logger.stubs(:debug)

    Thread.current[:session_context_runtime] = nil

    @runtime_mock = mock("runtime")
    @runtime_mock.stubs(:copy_to).returns(true)
    @runtime_mock.stubs(:exec).returns([[], [], 0])
    @runtime_mock.stubs(:copy_from).returns(nil)
    ContainerRuntime.stubs(:build).returns(@runtime_mock)
  end

  teardown do
    Thread.current[:session_context_runtime] = nil
  end

  # ====================================================================
  # AC 1: cursor_cli full pipeline
  # ====================================================================

  test "E2E cursor_cli: install command, context, skill dir, vscode settings, config.yaml" do
    run_full_pipeline("cursor_cli")
  end

  # ====================================================================
  # AC 2: claude_code full pipeline
  # ====================================================================

  test "E2E claude_code: install command, context, skill dir, vscode settings, config.yaml" do
    run_full_pipeline("claude_code")
  end

  # ====================================================================
  # AC 3: codex full pipeline
  # ====================================================================

  test "E2E codex: install command, context, skill dir, vscode settings, config.yaml" do
    run_full_pipeline("codex")
  end

  # ====================================================================
  # AC 4: gemini_cli full pipeline
  # ====================================================================

  test "E2E gemini_cli: install command, context, skill dir, vscode settings, config.yaml" do
    run_full_pipeline("gemini_cli")
  end

  # ====================================================================
  # AC 5: files.exclude covers all BMAD hidden paths for every runtime
  # ====================================================================

  test "E2E all runtimes: VS Code files.exclude contains all BMAD hidden paths" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      vscode_settings = capture_vscode_settings(session)

      BmadMethodInjector::BMAD_HIDDEN_PATHS.each do |path|
        assert_equal true, vscode_settings.dig("files.exclude", path),
          "#{agent_type}: Expected files.exclude to contain #{path}"
      end
    end
  end

  # ====================================================================
  # Cross-runtime: agent_type → tool flag mapping is exhaustive
  # ====================================================================

  test "E2E: AGENT_TYPE_TO_BMAD_TOOL covers all 4 runtimes" do
    AGENT_RUNTIMES.each do |agent_type, spec|
      assert_equal spec[:tool_flag], BmadMethodInjector::AGENT_TYPE_TO_BMAD_TOOL[agent_type],
        "Expected #{agent_type} to map to --tools #{spec[:tool_flag]}"
    end
  end

  # ====================================================================
  # Cross-runtime: BMAD_HIDDEN_PATHS covers all skill directories
  # ====================================================================

  test "E2E: BMAD_HIDDEN_PATHS includes skill dirs for all runtimes" do
    expected_skill_paths = %w[.cursor/skills .claude/skills .agents/skills .gemini/skills]
    expected_skill_paths.each do |path|
      assert_includes BmadMethodInjector::BMAD_HIDDEN_PATHS, path,
        "Expected BMAD_HIDDEN_PATHS to include #{path}"
    end
  end

  # ====================================================================
  # Cross-runtime: context includes <bmad-method> section
  # ====================================================================

  test "E2E: context file contains bmad-method section for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      result = SessionContextConstructor.build_result(session)

      bmad_section = result.sections.find { |s| s.tag == "bmad-method" }
      assert_not_nil bmad_section, "#{agent_type}: Expected bmad-method section in context"
      assert_includes result.applied_builders, "bmad_method",
        "#{agent_type}: Expected bmad_method in applied builders"
    end
  end

  # ====================================================================
  # Cross-runtime: config.yaml includes user name and language
  # ====================================================================

  test "E2E: install command includes user name for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      captured_cmd = capture_install_command(session)

      assert_includes captured_cmd, "--user-name Maria_Garcia",
        "#{agent_type}: Expected --user-name in install command"
    end
  end

  test "E2E: install command includes communication language for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      captured_cmd = capture_install_command(session)

      assert_includes captured_cmd, "--communication-language Spanish",
        "#{agent_type}: Expected --communication-language Spanish in install command"
    end
  end

  # ====================================================================
  # Cross-runtime: full assemble_session_context integration
  # ====================================================================

  test "E2E: assemble_session_context calls BmadMethodInjector for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type, mode: "interactive")

      injector_mock = mock("bmad_injector_#{agent_type}")
      injector_mock.expects(:inject!).once
      BmadMethodInjector.expects(:new).with("ctr-e2e", session, runtime: @runtime_mock)
                        .returns(injector_mock)

      SessionContextService.assemble_session_context("ctr-e2e", session)
    end
  end

  # ====================================================================
  # Cross-runtime: context metadata records successful install
  # ====================================================================

  test "E2E: successful install records success status for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      runtime = mock("runtime_#{agent_type}")
      runtime.stubs(:exec).returns([[], [], 0])

      BmadMethodInjector.new("cid-e2e", session, runtime: runtime).inject!

      session.reload
      assert_equal "success", session.context_metadata["bmad_install_status"],
        "#{agent_type}: Expected bmad_install_status to be 'success'"
      assert_nil session.context_metadata["bmad_install_error"],
        "#{agent_type}: Expected no bmad_install_error"
    end
  end

  # ====================================================================
  # Cross-runtime: failed install still allows session to proceed
  # ====================================================================

  test "E2E: failed install records failure and does not raise for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      runtime = mock("runtime_#{agent_type}")
      runtime.stubs(:exec).returns([[], ["npm ERR!"], 1])

      assert_nothing_raised do
        BmadMethodInjector.new("cid-e2e", session, runtime: runtime).inject!
      end

      session.reload
      assert_equal "failed", session.context_metadata["bmad_install_status"],
        "#{agent_type}: Expected bmad_install_status to be 'failed'"
      assert session.context_metadata["bmad_install_error"].present?,
        "#{agent_type}: Expected bmad_install_error to be present"
    end
  end

  # ====================================================================
  # Cross-runtime: context skips bmad-method when install failed
  # ====================================================================

  test "E2E: context builder skips bmad-method when install failed for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      session.update_column(:context_metadata, {
        "bmad_install_status" => "failed",
        "bmad_install_error" => "timed out"
      })

      result = SessionContextConstructor.build_result(session)

      assert_includes result.skipped_builders, "bmad_method",
        "#{agent_type}: Expected bmad_method to be skipped after failed install"
      bmad_section = result.sections.find { |s| s.tag == "bmad-method" }
      assert_nil bmad_section,
        "#{agent_type}: Expected no bmad-method section after failed install"
    end
  end

  # ====================================================================
  # Cross-runtime: default modules (bmm) and custom modules
  # ====================================================================

  test "E2E: default modules passed to install for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      captured_cmd = capture_install_command(session)

      assert_includes captured_cmd, "--modules bmm",
        "#{agent_type}: Expected default --modules bmm"
    end
  end

  test "E2E: custom modules passed to install for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type, bmad_modules: %w[bmm cis bmb])
      captured_cmd = capture_install_command(session)

      assert_includes captured_cmd, "--modules bmm,cis,bmb",
        "#{agent_type}: Expected --modules bmm,cis,bmb"
    end
  end

  # ====================================================================
  # Cross-runtime: bmad context content references
  # ====================================================================

  test "E2E: context content includes BMAD root and core config for all runtimes" do
    AGENT_RUNTIMES.each_key do |agent_type|
      session = create_bmad_session(agent_type)
      result = SessionContextConstructor.build_result(session)
      bmad_section = result.sections.find { |s| s.tag == "bmad-method" }

      assert_includes bmad_section.content, "/workspace/_bmad/",
        "#{agent_type}: Expected BMAD root path in context"
      assert_includes bmad_section.content, "/workspace/_bmad/core/config.yaml",
        "#{agent_type}: Expected core config path in context"
      assert_includes bmad_section.content, "/workspace/outputs/",
        "#{agent_type}: Expected output folder in context"
    end
  end

  # ====================================================================
  # Cross-runtime: skill files target correct directories per adapter
  # ====================================================================

  test "E2E: skill_files produce correct paths for all runtimes" do
    skill = OpenStruct.new(name: "test-skill", content: "# Test", title: "Test Skill",
                           description: "A test skill")

    expected_paths = {
      "cursor_cli" => "/home/cursor/.cursor/skills/test-skill/SKILL.md",
      "claude_code" => "/home/claude/.claude/skills/test-skill.md",
      "codex" => "/home/codex/.codex/skills/test-skill/SKILL.md",
      "gemini_cli" => "/home/gemini/.gemini/GEMINI.md"
    }

    expected_paths.each do |agent_type, expected_path|
      adapter = AgentCredentialsService.for(agent_type).adapter
      files = adapter.skill_files([skill])

      assert files.key?(expected_path),
        "#{agent_type}: Expected skill at #{expected_path}, got #{files.keys.inspect}"
      assert files[expected_path].present?,
        "#{agent_type}: Expected non-empty skill content at #{expected_path}"
    end
  end

  # ====================================================================
  # Cross-runtime: context file written to correct path per adapter
  # ====================================================================

  test "E2E: context_file_path is correct for all runtimes" do
    AGENT_RUNTIMES.each do |agent_type, spec|
      adapter = AgentCredentialsService.for(agent_type).adapter
      assert_equal spec[:context_path], adapter.context_file_path,
        "#{agent_type}: Expected context file at #{spec[:context_path]}"
    end
  end

  # ====================================================================
  # Full pipeline: assemble_session_context writes context + runs BMAD
  # ====================================================================

  test "E2E: full pipeline writes context file and runs BMAD for all runtimes" do
    AGENT_RUNTIMES.each do |agent_type, spec|
      session = create_bmad_session(agent_type, mode: "interactive")

      context_written = false
      bmad_install_called = false

      runtime = mock("runtime_full_#{agent_type}")
      runtime.stubs(:copy_from).returns(nil)

      runtime.stubs(:copy_to).with do |_ctr, path, content|
        context_written = true if path == spec[:context_path] && content.include?("<bmad-method")
        true
      end.returns(true)

      runtime.stubs(:exec).with do |_ctr, cmd|
        if cmd.is_a?(Array)
          full = cmd.join(" ")
          if full.include?("npx bmad-method install")
            bmad_install_called = true
          end
        end
        true
      end.returns([[], [], 0])

      Thread.current[:session_context_runtime] = nil
      ContainerRuntime.stubs(:build).returns(runtime)

      SessionContextService.assemble_session_context("ctr-full-#{agent_type}", session)

      assert context_written,
        "#{agent_type}: Expected context file written to #{spec[:context_path]}"
      assert bmad_install_called,
        "#{agent_type}: Expected npx bmad-method install to be called"
    end
  end

  private

  def create_bmad_session(agent_type, mode: nil, bmad_modules: nil)
    config = { "bmad_enabled" => true }
    config["bmad_modules"] = bmad_modules if bmad_modules

    attrs = {
      user: @user,
      project: @project,
      agent_type: agent_type,
      session_type: "agent_session",
      session_config: config
    }
    attrs[:mode] = mode if mode

    create(:terminal_session, **attrs)
  end

  def capture_install_command(session)
    captured_cmd = nil
    runtime = mock("runtime_capture")
    runtime.stubs(:exec).with do |_cid, cmd|
      if cmd.is_a?(Array)
        full = cmd.join(" ")
        captured_cmd = full if full.include?("npx bmad-method install")
      end
      true
    end.returns([[], [], 0])

    BmadMethodInjector.any_instance.stubs(:hide_bmad_in_vscode)
    BmadMethodInjector.new("cid-cap", session, runtime: runtime).inject!

    assert_not_nil captured_cmd, "Expected install command to be captured"
    captured_cmd
  end

  def capture_vscode_settings(session)
    runtime = mock("runtime_vscode")
    captured_cmd = nil

    runtime.stubs(:exec).with do |_cid, cmd|
      if cmd.is_a?(Array) && cmd[0] == "cat" && cmd[1] == BmadMethodInjector::VSCODE_SETTINGS_PATH
        true
      elsif cmd.is_a?(Array) && cmd[0] == "sh" && cmd[1] == "-c"
        captured_cmd = cmd[2] if cmd[2].to_s.include?("base64")
        true
      else
        true
      end
    end.returns([[], [], 0])

    BmadMethodInjector.new("cid-vs", session, runtime: runtime).inject!

    assert_not_nil captured_cmd, "Expected VS Code settings write command"
    base64_content = captured_cmd[/echo '([^']+)' \| base64 -d/, 1]
    JSON.parse(Base64.decode64(base64_content))
  end

  def run_full_pipeline(agent_type)
    spec = AGENT_RUNTIMES[agent_type]
    session = create_bmad_session(agent_type)

    # 1. Verify install command has correct --tools flag
    captured_cmd = capture_install_command(session)
    assert_includes captured_cmd, "--tools #{spec[:tool_flag]}",
      "Expected --tools #{spec[:tool_flag]}"
    assert_includes captured_cmd, "--user-name Maria_Garcia"
    assert_includes captured_cmd, "--communication-language Spanish"
    assert_includes captured_cmd, "--yes"
    assert_includes captured_cmd, "--directory /workspace"
    assert_includes captured_cmd, "--modules bmm"
    assert_includes captured_cmd, "npx bmad-method install"

    # 2. Verify context contains <bmad-method> section
    result = SessionContextConstructor.build_result(session)
    assert_includes result.applied_builders, "bmad_method"
    bmad_section = result.sections.find { |s| s.tag == "bmad-method" }
    assert_not_nil bmad_section
    assert_includes bmad_section.content, "/workspace/_bmad/"
    assert_includes bmad_section.content, "/workspace/_bmad/core/config.yaml"

    # 3. Verify VS Code settings contain all BMAD hidden paths
    fresh_session = create_bmad_session(agent_type)
    vscode_settings = capture_vscode_settings(fresh_session)
    BmadMethodInjector::BMAD_HIDDEN_PATHS.each do |path|
      assert_equal true, vscode_settings.dig("files.exclude", path),
        "Expected files.exclude to contain #{path}"
    end

    # 4. Verify skill directory is correct for this runtime
    adapter = AgentCredentialsService.for(agent_type).adapter
    assert_equal spec[:context_path], adapter.context_file_path

    # 5. Verify successful install records status
    success_session = create_bmad_session(agent_type)
    success_runtime = mock("runtime_success_#{agent_type}")
    success_runtime.stubs(:exec).returns([[], [], 0])
    BmadMethodInjector.new("cid-ok", success_session, runtime: success_runtime).inject!
    success_session.reload
    assert_equal "success", success_session.context_metadata["bmad_install_status"]
  end
end
