# frozen_string_literal: true

# BmadMethodInjector
# Installs BMAD Method into an agent container by running `npx bmad-method install`
# with the appropriate flags for the agent runtime, user language, and selected modules.
#
# Called during session setup (before_exec) when bmad_enabled is true.
class BmadMethodInjector
  AGENT_TYPE_TO_BMAD_TOOL = {
    "cursor_cli" => "cursor",
    "claude_code" => "claude-code",
    "codex" => "codex",
    "gemini_cli" => "gemini"
  }.freeze

  BMAD_HIDDEN_PATHS = %w[
    _bmad
    .cursor/skills
    .claude/skills
    .agents/skills
    .gemini/skills
  ].freeze

  VSCODE_SETTINGS_PATH = "/workspace/.vscode/settings.json"

  LANGUAGE_CODE_TO_NAME = {
    "en" => "English",
    "ru" => "Russian",
    "es" => "Spanish",
    "zh" => "Chinese",
    "fr" => "French",
    "de" => "German",
    "ja" => "Japanese",
    "pt" => "Portuguese",
    "it" => "Italian",
    "pl" => "Polish",
    "uk" => "Ukrainian"
  }.freeze

  DEFAULT_LANGUAGE = "English"

  INSTALL_TIMEOUT = 60

  class InstallError < StandardError; end

  def initialize(container_id, session, runtime:)
    @container_id = container_id
    @session = session
    @runtime = runtime
  end

  def inject!
    Timeout.timeout(INSTALL_TIMEOUT) do
      run_bmad_install
      hide_bmad_in_vscode
    end
    record_install_status("success")
  rescue Timeout::Error
    Rails.logger.warn("[BmadMethodInjector] Install timed out after #{INSTALL_TIMEOUT}s, proceeding without BMAD")
    record_install_status("failed", error: "Installation timed out after #{INSTALL_TIMEOUT}s")
  rescue StandardError => e
    Rails.logger.warn("[BmadMethodInjector] Install failed: #{e.message}, proceeding without BMAD")
    record_install_status("failed", error: e.message)
  end

  private

  attr_reader :container_id, :session, :runtime

  def run_bmad_install
    cmd = build_install_command
    result = runtime.exec(container_id, [ "sh", "-c", cmd ])
    exit_code = result[2].to_i

    if exit_code.zero?
      Rails.logger.info("[BmadMethodInjector] BMAD installed in container #{container_id}")
    else
      stderr = Array(result[1]).join
      Rails.logger.error("[BmadMethodInjector] Install failed (exit #{exit_code}): #{stderr}")
      raise InstallError, "npx bmad-method install failed with exit code #{exit_code}: #{stderr}"
    end
  end

  def hide_bmad_in_vscode
    existing_json = read_vscode_settings
    settings = parse_or_create_settings(existing_json)
    settings["files.exclude"] ||= {}
    BMAD_HIDDEN_PATHS.each { |path| settings["files.exclude"][path] = true }
    write_vscode_settings(JSON.pretty_generate(settings))
  end

  def build_install_command
    parts = [ "npx bmad-method install" ]
    parts << "--directory /workspace"
    parts << "--tools #{resolve_tool}"
    modules = resolve_modules.join(",")
    parts << "--modules #{modules}" if modules.present?
    parts << "--user-name #{sanitize_cli_arg(resolve_user_name)}"
    parts << "--communication-language #{sanitize_cli_arg(resolve_language)}"
    parts << "--document-output-language English"
    parts << "--output-folder outputs"
    parts << "--yes"

    parts.join(" ")
  end

  # npx re-parses arguments and drops shell quoting,
  # so spaces in values break Commander.js option parsing.
  def sanitize_cli_arg(value)
    value.to_s.gsub(/\s+/, "_")
  end

  def resolve_tool
    tool = AGENT_TYPE_TO_BMAD_TOOL[session.agent_type]
    raise ArgumentError, "Unknown agent_type for BMAD: #{session.agent_type}" unless tool

    tool
  end

  def resolve_modules
    session.bmad_modules
  end

  def resolve_language
    code = session.user&.preferred_agent_language
    LANGUAGE_CODE_TO_NAME.fetch(code, DEFAULT_LANGUAGE)
  end

  def resolve_user_name
    session.user&.name.presence || session.user&.email || "Developer"
  end

  def read_vscode_settings
    result = runtime.exec(container_id, [ "cat", VSCODE_SETTINGS_PATH ])
    return nil unless result[2].to_i.zero?

    Array(result[0]).join.presence
  end

  def parse_or_create_settings(json_string)
    return {} if json_string.blank?

    JSON.parse(json_string)
  rescue JSON::ParserError => e
    Rails.logger.warn("[BmadMethodInjector] Malformed .vscode/settings.json, overwriting: #{e.message}")
    {}
  end

  def write_vscode_settings(json_content)
    encoded = Base64.strict_encode64(json_content)
    cmd = "mkdir -p /workspace/.vscode && echo '#{encoded}' | base64 -d > #{VSCODE_SETTINGS_PATH}"
    runtime.exec(container_id, [ "sh", "-c", cmd ])
  end

  def record_install_status(status, error: nil)
    meta = session.context_metadata || {}
    meta["bmad_install_status"] = status
    meta["bmad_install_error"] = error.to_s.truncate(500) if error
    session.update_column(:context_metadata, meta)
  rescue StandardError => e
    Rails.logger.warn("[BmadMethodInjector] Failed to record install status: #{e.message}")
  end
end
