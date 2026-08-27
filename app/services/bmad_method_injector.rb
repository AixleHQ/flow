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
    "gemini_cli" => "gemini",
    # BMAD has no `grok` platform. Grok CLI reads Claude Code's artifacts by design
    # (its `[compat.claude]` cells scan `.claude/skills`, `.claude/rules` and
    # `CLAUDE.md` and are on by default), so the claude-code install is what a Grok
    # session can actually consume — not a stand-in for a missing platform.
    "grok" => "claude-code"
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

  # Pinned to match _bmad/_config/manifest.yaml; bumping requires re-validating
  # skill target directories (cursor/codex/gemini moved to .agents/skills in 6.6.0).
  # Since 6.10.0 bmb/cis/wds are external modules fetched from GitHub during
  # install, so the container needs outbound access to github.com — and enough
  # api.github.com budget to resolve their tags, which is what #github_read_token
  # buys.
  # 6.11.0 marks wds deprecated: it is hidden from the interactive picker but
  # still installs when named explicitly via --modules, which is how we drive it.
  BMAD_METHOD_VERSION = "6.11.0"

  INSTALL_TIMEOUT = 300

  # How much of each captured stream survives into the recorded failure reason.
  # `bmad_install_error` is itself truncated to 500 chars when stored, so this
  # only has to keep the tail readable rather than bound the column.
  OUTPUT_EXCERPT_LIMIT = 800

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
    result = runtime.exec(container_id, [ "sh", "-c", cmd ], timeout: INSTALL_TIMEOUT)
    exit_code = result[2].to_i

    if exit_code.zero?
      Rails.logger.info("[BmadMethodInjector] BMAD installed in container #{container_id}")
    else
      details = install_failure_details(result)
      Rails.logger.error("[BmadMethodInjector] Install failed (exit #{exit_code}): #{details}")
      raise InstallError, "npx bmad-method install failed with exit code #{exit_code}: #{details}"
    end
  end

  # The installer explains why it gave up on STDOUT — its prompt/logger writes
  # there — while STDERR carries npm's noise. Reporting stderr alone made every
  # real failure read as an unrelated `npm warn deprecated glob@…` line, which is
  # exactly how a GitHub rate-limit refusal stayed invisible in production: the
  # recorded reason named a deprecation warning and the actual 403 was dropped.
  # Both streams are kept, stdout first, with the token scrubbed out of each.
  def install_failure_details(result)
    streams = {
      "stdout" => redact_token(Array(result[0]).join).strip,
      "stderr" => redact_token(Array(result[1]).join).strip
    }

    excerpts = streams.filter_map do |name, text|
      "#{name}: #{text.last(OUTPUT_EXCERPT_LIMIT)}" if text.present?
    end

    excerpts.presence&.join(" | ") || "no output captured"
  end

  def hide_bmad_in_vscode
    existing_json = read_vscode_settings
    settings = parse_or_create_settings(existing_json)
    settings["files.exclude"] ||= {}
    BMAD_HIDDEN_PATHS.each { |path| settings["files.exclude"][path] = true }
    write_vscode_settings(JSON.pretty_generate(settings))
  end

  def build_install_command
    parts = [ "npx -y bmad-method@#{BMAD_METHOD_VERSION} install" ]
    parts << "--directory /workspace"
    parts << "--tools #{resolve_tool}"
    modules = resolve_modules.join(",")
    parts << "--modules #{modules}" if modules.present?
    parts << "--user-name #{sanitize_cli_arg(resolve_user_name)}"
    parts << "--communication-language #{sanitize_cli_arg(resolve_language)}"
    parts << "--document-output-language English"
    parts << "--output-folder outputs"
    parts << "--yes"

    command = parts.join(" ")
    token = github_read_token
    return command if token.blank?

    "GITHUB_TOKEN=#{shell_quote(token)} #{command}"
  end

  # Every external module (`bmb`, `cis`, `wds`) has its stable tag resolved
  # through api.github.com — see the installer's
  # tools/installer/modules/channel-resolver.js, which sends an Authorization
  # header only when GITHUB_TOKEN is set. Unauthenticated that API allows 60
  # requests/hour PER SOURCE IP, and every agent container in a cluster NATs
  # through one address, so a busy project drains the hourly budget and each
  # later install aborts with a 403. The installer's own error text says to set
  # GITHUB_TOKEN; this reuses the scopeless public-read token the skills catalog
  # already carries (Settings.github.read_token). Absent, the install still runs
  # and simply keeps the anonymous budget it had before.
  #
  # Handed over as an argv-scoped env prefix rather than a file on disk: the
  # install shell runs as uid 1001 while ContainerRuntime#write_file writes as
  # root, so a token file in sticky /tmp is one that shell cannot unlink again,
  # and a leftover secret at rest is worse than an argv the same single-tenant
  # container already sees repo-scoped installation tokens through. It is
  # scrubbed from everything this class logs or records.
  def github_read_token
    Settings.github.read_token.presence
  end

  def redact_token(text)
    token = github_read_token
    return text if token.blank?

    text.gsub(token, "[REDACTED]")
  end

  # POSIX single-quoting: everything is literal inside '…', and an embedded
  # quote closes, escapes, and reopens. Tokens are opaque vendor strings, so
  # nothing here may assume they are shell-safe.
  #
  # The block form of gsub is required, not cosmetic: in a replacement STRING
  # `\'` is the post-match back-reference, so the escape would expand to the
  # rest of the token instead of a quote.
  def shell_quote(value)
    "'#{value.to_s.gsub("'") { "'\\''" }}'"
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
    code = SessionCompany.membership_for(session)&.preferred_agent_language
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
    runtime.write_file(container_id, VSCODE_SETTINGS_PATH, json_content)
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
