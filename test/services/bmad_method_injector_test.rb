# frozen_string_literal: true

require "test_helper"

class BmadMethodInjectorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company, preferred_agent_language: "en", name: "John Doe")
    @runtime = mock("runtime")

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    stub_hide_bmad
  end

  # ====================================================================
  # AC 1: cursor_cli → --tools cursor
  # ====================================================================

  test "cursor_cli session installs with --tools cursor" do
    session = build_bmad_session(agent_type: "cursor_cli")

    expect_exec_matching("--tools cursor")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 2: claude_code → --tools claude-code
  # ====================================================================

  test "claude_code session installs with --tools claude-code" do
    session = build_bmad_session(agent_type: "claude_code")

    expect_exec_matching("--tools claude-code")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 3: codex → --tools codex
  # ====================================================================

  test "codex session installs with --tools codex" do
    session = build_bmad_session(agent_type: "codex")

    expect_exec_matching("--tools codex")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 4: gemini_cli → --tools gemini
  # ====================================================================

  test "gemini_cli session installs with --tools gemini" do
    session = build_bmad_session(agent_type: "gemini_cli")

    expect_exec_matching("--tools gemini")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 5: Custom modules → --modules bmm,cis,bmb
  # ====================================================================

  test "passes bmad_modules as comma-separated --modules flag" do
    session = build_bmad_session(
      agent_type: "cursor_cli",
      bmad_modules: [ "bmm", "cis", "bmb" ]
    )

    expect_exec_matching("--modules bmm,cis,bmb")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  test "uses default modules (bmm) when bmad_modules is absent" do
    session = build_bmad_session(agent_type: "cursor_cli")

    expect_exec_matching("--modules bmm")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  test "omits --modules flag when bmad_modules is explicitly empty" do
    session = build_bmad_session(
      agent_type: "cursor_cli",
      bmad_modules: []
    )

    expect_exec_not_matching("--modules")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 6: preferred_agent_language "ru" → --communication-language Russian
  # ====================================================================

  test "maps user preferred_agent_language code to full language name" do
    user = create(:user, :admin, company: @company, preferred_agent_language: "ru", name: "Ivan Petrov")
    session = build_bmad_session(agent_type: "cursor_cli", user: user)

    expect_exec_matching("--communication-language Russian")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # AC 7: No preferred language → fallback --communication-language English
  # ====================================================================

  test "falls back to English when preferred_agent_language is nil" do
    user = create(:user, :admin, company: @company, preferred_agent_language: nil, name: "Jane Doe")
    session = build_bmad_session(agent_type: "cursor_cli", user: user)

    expect_exec_matching("--communication-language English")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # ====================================================================
  # Full command structure
  # ====================================================================

  test "builds complete npx command with all flags" do
    user = create(:user, :admin, company: @company, preferred_agent_language: "es", name: "Maria Garcia")
    session = build_bmad_session(
      agent_type: "claude_code",
      user: user,
      bmad_modules: [ "bmm", "cis" ]
    )

    captured_cmd = nil
    @runtime.expects(:exec).with do |cid, cmd|
      captured_cmd = cmd[2] if cmd.is_a?(Array)
      cid == "cid-1" && cmd.is_a?(Array)
    end.returns([ [], [], 0 ])

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!

    assert_includes captured_cmd, "npx -y bmad-method@#{BmadMethodInjector::BMAD_METHOD_VERSION} install"
    assert_includes captured_cmd, "--tools claude-code"
    assert_includes captured_cmd, "--user-name Maria_Garcia"
    assert_includes captured_cmd, "--communication-language Spanish"
    assert_includes captured_cmd, "--yes"
    assert_includes captured_cmd, "--modules bmm,cis"
    assert_includes captured_cmd, "--directory /workspace"
    assert_includes captured_cmd, "--output-folder outputs"
    assert_includes captured_cmd, "--document-output-language English"
  end

  test "includes --user-name from session user name" do
    session = build_bmad_session(agent_type: "cursor_cli")

    expect_exec_matching("--user-name John_Doe")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  test "includes --yes flag for non-interactive install" do
    session = build_bmad_session(agent_type: "cursor_cli")

    expect_exec_matching("--yes")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  test "includes --directory /workspace" do
    session = build_bmad_session(agent_type: "cursor_cli")

    expect_exec_matching("--directory /workspace")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  # The install pulls external modules over the network and routinely outruns
  # the runtime's default exec read timeout, which surfaced as a bogus
  # "read timeout reached" failure mid-install.
  test "passes INSTALL_TIMEOUT to the runtime so the exec is not cut short" do
    session = build_bmad_session(agent_type: "claude_code")

    # Match on the install command rather than on call order: inject! also execs
    # `cat` for the VS Code settings, and only the install carries the timeout.
    captured_opts = nil
    @runtime.stubs(:exec).with do |_cid, cmd, opts|
      captured_opts = opts if cmd.is_a?(Array) && cmd[2].to_s.include?("bmad-method@")
      true
    end.returns([ [], [], 0 ])

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!

    assert_equal BmadMethodInjector::INSTALL_TIMEOUT, captured_opts&.dig(:timeout)
  end

  # ====================================================================
  # AC 1: Install fails with non-zero exit → warn logged, session proceeds
  # ====================================================================

  test "non-zero exit code does not raise, logs warn, and records failure in context_metadata" do
    session = build_bmad_session(agent_type: "cursor_cli")

    @runtime.stubs(:exec).returns([ [], [ "npm ERR! not found" ], 1 ])

    Rails.logger.expects(:warn).with(regexp_matches(/Install failed.*proceeding without BMAD/)).at_least_once

    assert_nothing_raised do
      BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
    end

    session.reload
    assert_equal "failed", session.context_metadata["bmad_install_status"]
    assert_includes session.context_metadata["bmad_install_error"], "exit code 1"
  end

  # ====================================================================
  # AC 2: Install times out (>60s) → process killed, error logged, session proceeds
  # ====================================================================

  test "timeout does not raise, logs warn, and records failure in context_metadata" do
    session = build_bmad_session(agent_type: "cursor_cli")

    @runtime.stubs(:exec).with do |cid, cmd|
      raise Timeout::Error if cmd.is_a?(Array) && cmd[2].to_s.include?("npx")
      true
    end.returns([ [], [], 0 ])

    Rails.logger.expects(:warn).with(regexp_matches(/timed out.*proceeding without BMAD/)).at_least_once

    assert_nothing_raised do
      BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
    end

    session.reload
    assert_equal "failed", session.context_metadata["bmad_install_status"]
    assert_includes session.context_metadata["bmad_install_error"], "timed out"
  end

  # ====================================================================
  # AC 3: npx not available (Node.js missing) → error caught, session proceeds
  # ====================================================================

  test "Errno::ENOENT (npx missing) does not raise, logs warn, and records failure" do
    session = build_bmad_session(agent_type: "cursor_cli")

    @runtime.stubs(:exec).raises(Errno::ENOENT, "npx")

    Rails.logger.expects(:warn).with(regexp_matches(/Install failed.*proceeding without BMAD/)).at_least_once

    assert_nothing_raised do
      BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
    end

    session.reload
    assert_equal "failed", session.context_metadata["bmad_install_status"]
    assert_includes session.context_metadata["bmad_install_error"], "npx"
  end

  # ====================================================================
  # AC 4: Failure → context_metadata includes bmad_install_status and bmad_install_error
  # ====================================================================

  test "successful install records success status in context_metadata" do
    session = build_bmad_session(agent_type: "cursor_cli")

    @runtime.stubs(:exec).returns([ [], [], 0 ])

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!

    session.reload
    assert_equal "success", session.context_metadata["bmad_install_status"]
    assert_nil session.context_metadata["bmad_install_error"]
  end

  test "failure records both status and error in context_metadata" do
    session = build_bmad_session(agent_type: "cursor_cli")

    @runtime.stubs(:exec).returns([ [], [ "some error output" ], 127 ])

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!

    session.reload
    assert_equal "failed", session.context_metadata["bmad_install_status"]
    assert session.context_metadata["bmad_install_error"].present?
  end

  test "preserves existing context_metadata when recording install status" do
    session = build_bmad_session(agent_type: "cursor_cli")
    session.update_column(:context_metadata, { "session_id" => session.id, "built_at" => Time.current.iso8601 })

    @runtime.stubs(:exec).returns([ [], [], 0 ])

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!

    session.reload
    assert_equal "success", session.context_metadata["bmad_install_status"]
    assert_equal session.id, session.context_metadata["session_id"]
  end

  # ====================================================================
  # Error handling — ArgumentError for unknown agent_type
  # ====================================================================

  test "unknown agent_type does not raise, records failure" do
    session = create(:terminal_session, user: @user, agent_type: nil, session_type: "workflow_step", session_config: {
      "bmad_enabled" => true
    })

    assert_nothing_raised do
      BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
    end

    session.reload
    assert_equal "failed", session.context_metadata["bmad_install_status"]
  end

  # ====================================================================
  # Edge cases
  # ====================================================================

  test "falls back to email when user name is nil" do
    session = build_bmad_session(agent_type: "cursor_cli")
    session.user.stubs(:name).returns(nil)

    expect_exec_matching("--user-name #{@user.email.gsub(/\s+/, '_')}")

    BmadMethodInjector.new("cid-1", session, runtime: @runtime).inject!
  end

  test "maps all supported language codes" do
    expected = {
      "en" => "English", "ru" => "Russian", "es" => "Spanish",
      "zh" => "Chinese", "fr" => "French", "de" => "German",
      "ja" => "Japanese", "pt" => "Portuguese", "it" => "Italian",
      "pl" => "Polish", "uk" => "Ukrainian"
    }

    expected.each do |code, name|
      assert_equal name, BmadMethodInjector::LANGUAGE_CODE_TO_NAME[code],
        "Expected language code '#{code}' to map to '#{name}'"
    end
  end

  test "AGENT_TYPE_TO_BMAD_TOOL covers all valid agent types" do
    %w[cursor_cli claude_code codex gemini_cli].each do |agent_type|
      assert BmadMethodInjector::AGENT_TYPE_TO_BMAD_TOOL.key?(agent_type),
        "Missing BMAD tool mapping for #{agent_type}"
    end
  end

  # ====================================================================
  # BMAD_HIDDEN_PATHS constant
  # ====================================================================

  test "BMAD_HIDDEN_PATHS contains all required paths" do
    expected = %w[_bmad .cursor/skills .claude/skills .agents/skills .gemini/skills]
    assert_equal expected.sort, BmadMethodInjector::BMAD_HIDDEN_PATHS.sort
  end

  # ====================================================================
  # hide_bmad_in_vscode — AC 3: No existing settings file
  # ====================================================================

  test "hide_bmad_in_vscode creates new settings.json with BMAD exclusions when none exists" do
    session = build_bmad_session(agent_type: "cursor_cli")
    BmadMethodInjector.any_instance.unstub(:hide_bmad_in_vscode)
    injector = BmadMethodInjector.new("cid-1", session, runtime: @runtime)

    @runtime.expects(:exec)
      .with("cid-1", [ "cat", BmadMethodInjector::VSCODE_SETTINGS_PATH ])
      .returns([ [], [], 1 ])

    captured_content = nil
    @runtime.expects(:write_file)
      .with { |cid, path, content| cid == "cid-1" && path == BmadMethodInjector::VSCODE_SETTINGS_PATH && (captured_content = content) }
      .returns(true)

    injector.send(:hide_bmad_in_vscode)

    settings = JSON.parse(captured_content)
    assert_equal 5, settings["files.exclude"].size
    BmadMethodInjector::BMAD_HIDDEN_PATHS.each do |path|
      assert settings.dig("files.exclude", path), "Expected #{path} to be excluded"
    end
  end

  # ====================================================================
  # hide_bmad_in_vscode — AC 2: Existing settings file, merge
  # ====================================================================

  test "hide_bmad_in_vscode merges BMAD entries into existing settings" do
    session = build_bmad_session(agent_type: "cursor_cli")
    BmadMethodInjector.any_instance.unstub(:hide_bmad_in_vscode)
    injector = BmadMethodInjector.new("cid-1", session, runtime: @runtime)

    existing = {
      "editor.fontSize" => 14,
      "files.exclude" => { "node_modules" => true }
    }

    @runtime.expects(:exec)
      .with("cid-1", [ "cat", BmadMethodInjector::VSCODE_SETTINGS_PATH ])
      .returns([ [ JSON.generate(existing) ], [], 0 ])

    captured_content = nil
    @runtime.expects(:write_file)
      .with { |cid, path, content| cid == "cid-1" && path == BmadMethodInjector::VSCODE_SETTINGS_PATH && (captured_content = content) }
      .returns(true)

    injector.send(:hide_bmad_in_vscode)

    settings = JSON.parse(captured_content)
    assert_equal 14, settings["editor.fontSize"]
    assert settings.dig("files.exclude", "node_modules")
    BmadMethodInjector::BMAD_HIDDEN_PATHS.each do |path|
      assert settings.dig("files.exclude", path), "Expected #{path} to be excluded"
    end
  end

  test "hide_bmad_in_vscode preserves existing settings without files.exclude" do
    session = build_bmad_session(agent_type: "cursor_cli")
    BmadMethodInjector.any_instance.unstub(:hide_bmad_in_vscode)
    injector = BmadMethodInjector.new("cid-1", session, runtime: @runtime)

    existing = { "editor.tabSize" => 2, "terminal.integrated.fontSize" => 12 }

    @runtime.expects(:exec)
      .with("cid-1", [ "cat", BmadMethodInjector::VSCODE_SETTINGS_PATH ])
      .returns([ [ JSON.generate(existing) ], [], 0 ])

    captured_content = nil
    @runtime.expects(:write_file)
      .with { |cid, path, content| cid == "cid-1" && path == BmadMethodInjector::VSCODE_SETTINGS_PATH && (captured_content = content) }
      .returns(true)

    injector.send(:hide_bmad_in_vscode)

    settings = JSON.parse(captured_content)
    assert_equal 2, settings["editor.tabSize"]
    assert_equal 12, settings["terminal.integrated.fontSize"]
    assert_equal 5, settings["files.exclude"].size
  end

  # ====================================================================
  # hide_bmad_in_vscode — malformed JSON
  # ====================================================================

  test "hide_bmad_in_vscode overwrites malformed settings.json" do
    session = build_bmad_session(agent_type: "cursor_cli")
    BmadMethodInjector.any_instance.unstub(:hide_bmad_in_vscode)
    injector = BmadMethodInjector.new("cid-1", session, runtime: @runtime)

    @runtime.expects(:exec)
      .with("cid-1", [ "cat", BmadMethodInjector::VSCODE_SETTINGS_PATH ])
      .returns([ [ "{ invalid json }}}" ], [], 0 ])

    captured_content = nil
    @runtime.expects(:write_file)
      .with { |cid, path, content| cid == "cid-1" && path == BmadMethodInjector::VSCODE_SETTINGS_PATH && (captured_content = content) }
      .returns(true)

    injector.send(:hide_bmad_in_vscode)

    settings = JSON.parse(captured_content)
    assert_equal 5, settings["files.exclude"].size
  end

  # ====================================================================
  # hide_bmad_in_vscode — writes via runtime.write_file
  # ====================================================================

  test "hide_bmad_in_vscode writes via runtime write_file" do
    session = build_bmad_session(agent_type: "cursor_cli")
    BmadMethodInjector.any_instance.unstub(:hide_bmad_in_vscode)
    injector = BmadMethodInjector.new("cid-1", session, runtime: @runtime)

    @runtime.expects(:exec)
      .with("cid-1", [ "cat", BmadMethodInjector::VSCODE_SETTINGS_PATH ])
      .returns([ [], [], 1 ])

    @runtime.expects(:write_file)
      .with("cid-1", BmadMethodInjector::VSCODE_SETTINGS_PATH, anything)
      .returns(true)

    injector.send(:hide_bmad_in_vscode)
  end

  # ====================================================================
  # INSTALL_TIMEOUT constant
  # ====================================================================

  test "INSTALL_TIMEOUT is 300 seconds" do
    assert_equal 300, BmadMethodInjector::INSTALL_TIMEOUT
  end

  private

  def build_bmad_session(agent_type:, user: @user, bmad_modules: nil)
    config = { "bmad_enabled" => true }
    config["bmad_modules"] = bmad_modules if bmad_modules
    create(:terminal_session, user: user, agent_type: agent_type, session_config: config)
  end

  def stub_hide_bmad
    BmadMethodInjector.any_instance.stubs(:hide_bmad_in_vscode)
  end

  def expect_exec_matching(substring)
    @runtime.expects(:exec).with do |cid, cmd|
      cid == "cid-1" && cmd.is_a?(Array) && cmd[2].to_s.include?(substring)
    end.returns([ [], [], 0 ])
  end

  def expect_exec_not_matching(substring)
    @runtime.expects(:exec).with do |cid, cmd|
      cid == "cid-1" && cmd.is_a?(Array) && !cmd[2].to_s.include?(substring)
    end.returns([ [], [], 0 ])
  end
end
