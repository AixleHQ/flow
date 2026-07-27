# frozen_string_literal: true

module Agents
  # Claude Code adapter for credential handling
  # Config: ~/.claude.json
  # Docs: https://docs.anthropic.com/claude-code
  class ClaudeCodeAdapter < BaseAdapter
    CONFIG_VERSION = "2.1.14"
    METRIC_TOKENS_NAME = "claude_code.token.usage"
    METRIC_COST_NAME = "claude_code.cost.usage"
    LEGACY_METRIC_NAMES = {
      "terminal.session.tokens" => METRIC_TOKENS_NAME,
      "terminal.session.cost" => METRIC_COST_NAME
    }.freeze

    def self.default_config_paths
      [ "~/.claude/settings.json", "CLAUDE.md" ]
    end

    def config_path
      "#{home_dir}/.claude.json"
    end

    def auth_file_paths
      [
        "#{home_dir}/.claude.json",
        "#{home_dir}/.claude/.credentials.json",
        # Bedrock writes no token anywhere — the wizard records the choice here instead, so
        # this is the only file that can tell us a Bedrock login finished.
        "#{home_dir}/.claude/settings.json"
      ]
    end

    # Watch both auth files — primaryApiKey lands in .claude.json (API key path),
    # claudeAiOauth lands in .claude/.credentials.json (claude.ai OAuth path).
    def auth_watch_path
      auth_file_paths.join(",")
    end

    def home_dir
      "/home/claude"
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # Built-in Claude Code tools (always allowed). DesignSync is an aixle-provided
    # tool that must be allow-listed so it runs without a prompt.
    BUILTIN_TOOLS = %w[Task Bash Glob Grep LS Read Edit MultiEdit Write WebFetch WebSearch DesignSync].freeze

    def allowed_tools(mcp_server_names = [])
      mcp_permissions = mcp_server_names.map { |name| "mcp__#{name}" }
      BUILTIN_TOOLS + mcp_permissions
    end

    # Keys that indicate auth is complete (watcher uses dot-notation for nested).
    # Two real-token sources, depending on login method:
    #   - primaryApiKey                — written to ~/.claude.json after platform.claude.com (API key)
    #   - claudeAiOauth.accessToken    — written to ~/.claude/.credentials.json after claude.ai (OAuth)
    # We wait specifically for these because oauthAccount alone is just metadata
    # and lands before the token, causing a race.
    # The watcher checks these against every watched path, any-match, so the Bedrock marker
    # simply becomes a third way to be finished. No watcher change needed.
    def auth_required_keys
      %w[primaryApiKey claudeAiOauth.accessToken env.CLAUDE_CODE_USE_BEDROCK]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["primaryApiKey"].present? ||
        config.dig("claudeAiOauth", "accessToken").present? ||
        # Bedrock produces no token to wait for. The wizard writing this marker into
        # settings.json is the completion signal.
        config.dig("env", "CLAUDE_CODE_USE_BEDROCK").present?
    end

    # /design-login layers a `designOauth` block onto an EXISTING Claude login. It is
    # the one "design" concept in the codebase — the AgentAuthStrategy is generic and
    # only sees an opaque `kind`; everything design-specific lives in these overrides.
    DESIGN_KIND = "design"

    # Seed the user's existing base login (minus any designOauth) so the CLI starts
    # authenticated; the session then only adds the fresh designOauth block. Stripping
    # designOauth matters on RECONNECT — otherwise the token the watcher waits for is
    # present from the start and completes instantly.
    def auth_setup_files_for(kind, current_config = nil)
      return config_files((current_config || {}).except("designOauth")) if kind == DESIGN_KIND

      # Seed the platform's AWS profile into the auth container so Claude Code's own
      # Bedrock wizard lists it. The helper it points at has no connection yet — and the
      # wizard EXECUTES credential_process during verification, so the helper reporting
      # "not connected" is precisely how we learn the user chose Bedrock inside the TUI,
      # before anything is written to disk.
      super.merge(aws_config_file(AUTH_SEED_BEDROCK))
    end

    # Wait for the design block specifically (the base token is injected up-front).
    def auth_required_keys_for(kind)
      kind == DESIGN_KIND ? %w[designOauth.accessToken] : super
    end

    def auth_complete_for?(kind, config_content)
      return super unless kind == DESIGN_KIND

      parse_json(config_content).dig("designOauth", "accessToken").present?
    end

    # Launch the CLI already running /design-login (the prompt is passed on the command
    # line as ONE command, so there's no delay before it appears). The CLI is already
    # logged in via the seeded creds; the user just approves in the browser.
    def auth_launch_commands_for(kind)
      kind == DESIGN_KIND ? [ "claude /design-login" ] : super
    end

    # Design only ADDS the freshly-minted designOauth to the existing credential. It
    # must NOT re-capture the base from the container: the base was injected there, and
    # a full re-scrape would resurrect a stale base login (e.g. an old claudeAiOauth)
    # next to the real one → Claude's "Both claude.ai and /login managed key set".
    def reconcile_captured_credentials(kind, current, captured)
      if kind == DESIGN_KIND
        design = captured[DESIGN_KEY]
        return current || {} unless design.is_a?(Hash) && design["accessToken"].present?

        return (current || {}).merge(DESIGN_KEY => design)
      end

      current ||= {}

      # A cloud connection is NOT scraped from the container — the connect flow stored it
      # server-side. The default behaviour here is a full replace, which would destroy it
      # (refresh token included) the moment an auth session completed. So merge the stored
      # block forward, folding in whatever non-secret config the wizard chose.
      merged_block = merge_bedrock_blocks(current[BEDROCK_KEY], captured[BEDROCK_KEY])

      result = captured.except(BEDROCK_KEY)
      result[BEDROCK_KEY] = merged_block if merged_block.present?

      # Carry the design token across a login it had nothing to do with.
      stored_design = current[DESIGN_KEY]
      result[DESIGN_KEY] = stored_design if stored_design.present? && result[DESIGN_KEY].blank?

      keep_single_inference(result, chosen_inference(captured) || chosen_inference(current))
    end

    # An auth session is the only place a base actually changes, so it is the only place the
    # other inference credentials are dropped. A working session's read-back must never do
    # this: nothing was chosen there, and the container legitimately lacks whatever the
    # active provider does not render.
    def keep_single_inference(config, active)
      return config if active.blank?

      config.except(*(INFERENCE_KEYS - [ active ]))
    end

    # What the given config says inference runs on. A Bedrock block means Claude Code's own
    # wizard wrote CLAUDE_CODE_USE_BEDROCK, which beats any Anthropic-side token.
    def chosen_inference(config)
      return nil if config.blank?
      return BEDROCK_KEY if config[BEDROCK_KEY].present?
      return "claudeAiOauth" if config.dig("claudeAiOauth", "accessToken").present?
      return "primaryApiKey" if config["primaryApiKey"].present?

      nil
    end

    def merge_bedrock_blocks(stored, from_wizard)
      return stored if from_wizard.blank?
      return from_wizard if stored.blank?

      # The wizard's values win for what it actually decided; everything it knows nothing
      # about (identity_center, role, credential_process) survives untouched.
      merged = stored.merge(from_wizard.except("models"))
      models = (stored["models"] || {}).merge(from_wizard["models"] || {})
      merged["models"] = models if models.present?
      merged
    end

    # Soonest OAuth-token expiry (epoch ms) across all present blocks
    # (claudeAiOauth + designOauth), or nil if none carry one. Used to (a) populate
    # agent_credentials.expires_at and (b) drive the proactive-refresh sweep so we
    # fire when whichever block expires first is near expiry.
    def token_expires_at(credentials)
      OAUTH_BLOCKS.filter_map { |b| credentials.dig(b, "expiresAt") }.map(&:to_i).min
    end

    # Claude stores two independently-rotating OAuth blocks: claudeAiOauth (base login)
    # and designOauth (/design-login). Merge each block on its own expiry so that
    # (a) adding designOauth isn't skipped just because claudeAiOauth didn't change, and
    # (b) a session without design access never wipes a stored designOauth.
    OAUTH_BLOCKS = %w[claudeAiOauth designOauth].freeze

    # Proactive server-side token refresh (Temporal sweep).
    REFRESH_MARGIN_MS = 15 * 60 * 1000 # refresh a block if it expires within 15 min (or already expired)
    OAUTH_TOKEN_URL   = "https://platform.claude.com/v1/oauth/token"
    # Base (claude.ai) login client_id. Prefer Settings; fall back to the known public client id.
    BASE_OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    def merge_refreshed_credentials(current, incoming)
      merged = current.merge(incoming) # incoming wins for scalar keys (userID, oauthAccount, primaryApiKey, ...)
      OAUTH_BLOCKS.each do |block|
        picked = freshest_oauth_block(current[block], incoming[block])
        if picked.present?
          merged[block] = picked
        else
          merged.delete(block)
        end
      end

      # The cloud connection must never be treated as a scalar. The container only ever sees
      # the rendered half of it (region, profile, model pins) — the Identity Center
      # registration and tokens live server-side and are absent from anything scraped back
      # out. Letting incoming win wholesale destroys them, refresh token included.
      cloud = merge_bedrock_blocks(current[BEDROCK_KEY], incoming[BEDROCK_KEY])
      if cloud.present?
        merged[BEDROCK_KEY] = cloud
      else
        merged.delete(BEDROCK_KEY)
      end

      merged
    end

    # Proactively refresh any OAuth block within the refresh margin, server-side.
    # Each block (claudeAiOauth base login + designOauth) rotates independently, so
    # we refresh only the blocks that are near expiry and persist under a row lock
    # via merge_refreshed_credentials + from_artifacts so a concurrent live session's
    # cleanup can't clobber the rotated token.
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :not_needed | :error, detail: String | nil }
    def refresh!(credential)
      current = credential.config_data
      now_ms  = (Time.current.to_f * 1000).to_i
      refreshed_blocks = {}
      error = nil

      OAUTH_BLOCKS.each do |block_name|
        block = current[block_name]
        next unless block.is_a?(Hash) && block["refreshToken"].present?

        exp = block["expiresAt"].to_i
        # refresh if expired or within the margin
        next unless exp.positive? && (exp - now_ms) <= REFRESH_MARGIN_MS

        client_id = block_name == "designOauth" ? block["clientId"] : base_oauth_client_id
        new_block = request_oauth_refresh(client_id: client_id, refresh_token: block["refreshToken"],
                                          previous: block, now_ms: now_ms)
        if new_block
          refreshed_blocks[block_name] = new_block
        else
          error ||= "#{block_name} refresh failed"
        end
      end

      return { status: :error,      detail: error } if refreshed_blocks.empty? && error
      return { status: :not_needed, detail: nil }   if refreshed_blocks.empty?

      credential.with_lock do
        fresh    = credential.config_data
        incoming = fresh.merge(refreshed_blocks)                # only the blocks we refreshed change
        merged   = merge_refreshed_credentials(fresh, incoming) # existing per-block freshest guard
        AgentCredential.from_artifacts(credential.user_id, credential.company_id, "claude_code", merged) if merged != fresh
      end

      { status: :refreshed, detail: error } # partial failure (one block ok, one failed) still counts as refreshed
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "oauthAccount",          # OAuth account metadata (.claude.json)
        "primaryApiKey",         # API key (.claude.json, platform.claude.com path)
        "customApiKeyResponses", # approved/rejected API keys (.claude.json)
        "userID",                # user identifier (.claude.json)
        "claudeAiOauth",         # OAuth tokens (.claude/.credentials.json, claude.ai path)
        "designOauth"            # design tokens from /design-login (.credentials.json): user:design:read/write
      ).compact
    end

    # Generate ~/.claude.json content. Excludes claudeAiOauth + designOauth
    # (both live in .credentials.json, never in .claude.json).
    def generate_config(credentials, workflow_config = {})
      {
        # Credentials from database (API-key path fields, OAuth account metadata, userID, etc.)
        **credentials.except("claudeAiOauth", "designOauth"),

        # Fixed values (skip onboarding, etc.)
        "installMethod" => "global",
        "hasCompletedOnboarding" => true,
        "lastOnboardingVersion" => CONFIG_VERSION,
        "numStartups" => 1,
        "effortCalloutV2Dismissed" => true,

        # Project config (generated based on workflow)
        "projects" => generate_projects_config(workflow_config)
      }
    end

    # Override to write multiple config files. The set depends on which auth path
    # the user used: claude.ai OAuth credentials live in a separate file.
    def config_files(credentials, workflow_config = {})
      mcp_names = workflow_config[:enabled_mcp_servers] || []
      model = workflow_config[:model]
      bedrock = bedrock_block(credentials)
      # Render only the credential inference actually runs on. Handing the container a second
      # one produces Claude Code's "Both claude.ai and /login managed key set" state, and
      # makes it unknowable from the outside which credential a request used.
      credentials = keep_single_inference(credentials, chosen_inference(credentials))
      files = {
        # Main config (includes primaryApiKey for API-key path users)
        config_path => generate_config(credentials, workflow_config).to_json,
        # Settings with permissions and optional model override
        "#{home_dir}/.claude/settings.json" => generate_settings(mcp_names, model: model, bedrock: bedrock).to_json
      }
      files.merge!(aws_config_file(bedrock)) if bedrock

      # .credentials.json carries the claude.ai OAuth token and, if the user has run
      # /design-login, the separate designOauth token (user:design:read/write). Both
      # are written into the same file, mirroring Claude Code's own layout.
      creds_file = {}
      oauth = credentials["claudeAiOauth"]
      creds_file["claudeAiOauth"] = oauth if oauth.is_a?(Hash) && oauth["accessToken"].present?
      design = credentials["designOauth"]
      creds_file["designOauth"] = design if design.is_a?(Hash) && design["accessToken"].present?
      files["#{home_dir}/.claude/.credentials.json"] = creds_file.to_json if creds_file.any?

      files
    end

    # == Amazon Bedrock (bring-your-own cloud account) ==
    #
    # A user who bills through their own AWS account carries an `awsBedrock` block in
    # the credential, alongside claudeAiOauth/primaryApiKey. The block is config, not a
    # secret: it names a credential source (a credential_process helper backed by our
    # vending endpoint, or an IAM Identity Center profile) that is resolved inside the
    # container at use time.
    #
    # Everything here is rendered into the USER settings file and ~/.aws/config — never
    # into managed settings and never into process env — so a repo's own committed
    # .claude/settings.json (project scope, which outranks user scope) still wins.
    # See docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md.
    BEDROCK_KEY = "awsBedrock"

    # Where a Claude model's tokens are billed. Exactly one of these is ever stored: Claude
    # Code picks its provider from env, so a second one would sit there doing nothing while
    # the UI could not say which is live. Ordered by which wins at runtime — the Bedrock env
    # beats any Anthropic-side token.
    INFERENCE_KEYS = [ BEDROCK_KEY, "claudeAiOauth", "primaryApiKey" ].freeze

    # Design has its own authorization and is orthogonal to where inference is billed, so it
    # survives a change of inference credential.
    DESIGN_KEY = "designOauth"

    # Alias → the env var Claude Code reads for it on Bedrock. Pinning is mandatory:
    # an unpinned deployment resolves the primary model to Opus and bills at Opus rates.
    BEDROCK_MODEL_ENV = {
      "opus" => "ANTHROPIC_DEFAULT_OPUS_MODEL",
      "sonnet" => "ANTHROPIC_DEFAULT_SONNET_MODEL",
      "haiku" => "ANTHROPIC_DEFAULT_HAIKU_MODEL"
    }.freeze

    # Claude Code aborts credential-chain resolution after 60s by default. A brokered
    # source needs a network round-trip, so give it room — without letting a hung
    # helper wedge the session for minutes.
    BEDROCK_CHAIN_RESOLVE_TIMEOUT_MS = 120_000

    # The profile handed to an auth container, before any connection exists. Region is
    # Claude Code's own Bedrock fallback; the real one comes from the connection once the
    # user has made one.
    AUTH_SEED_BEDROCK = {
      "region" => "us-east-1",
      "profile" => CloudAuth::AwsDeviceFlow::DEFAULT_PROFILE,
      "credential_process" => CloudAuth::AwsDeviceFlow::CREDENTIAL_PROCESS_PATH
    }.freeze

    # With Bedrock active, any of these shadows it: an API key or auth token wins over
    # the AWS credential chain, another provider toggle switches endpoints outright, and
    # ANTHROPIC_BASE_URL points at the first-party API. The Bedrock gateway override is
    # ANTHROPIC_BEDROCK_BASE_URL and is deliberately not on this list.
    BEDROCK_CONFLICTING_ENV = %w[
      ANTHROPIC_API_KEY
      ANTHROPIC_AUTH_TOKEN
      ANTHROPIC_BASE_URL
      CLAUDE_CODE_USE_VERTEX
      CLAUDE_CODE_USE_FOUNDRY
    ].freeze

    # What we keep from the settings file the Bedrock wizard wrote.
    #
    # This follows the platform's existing pattern: whatever the CLI itself persisted during
    # login gets sliced and stored, exactly as `primaryApiKey` is. The doctrine in
    # oauth-implementation.md §9 rules out a static-key *form* as the primary UX, not keeping
    # a credential the CLI wrote — and without keeping it, a user who pastes a Bedrock API
    # key at the wizard's prompt loses it the moment the container is replaced.
    #
    # The model pins matter for a different reason: we regenerate this settings file from the
    # connection every session, so a pin that is not stored here disappears — and an unpinned
    # deployment on Bedrock resolves to Opus and bills at Opus rates.
    WIZARD_MODEL_ENV = BEDROCK_MODEL_ENV.invert.freeze

    def extract_settings_config(content)
      settings = parse_json(content)
      env = settings["env"] || {}
      return {} if env["CLAUDE_CODE_USE_BEDROCK"].blank?

      block = {
        "region" => env["AWS_REGION"],
        "profile" => env["AWS_PROFILE"],
        "bearer_token" => env["AWS_BEARER_TOKEN_BEDROCK"]
      }.compact_blank

      static = static_credentials_from(env)
      block["static_credentials"] = static if static.present?

      models = WIZARD_MODEL_ENV.each_with_object({}) do |(env_key, model_alias), acc|
        acc[model_alias] = env[env_key] if env[env_key].present?
      end
      block["models"] = models if models.present?
      available = settings["availableModels"]
      block["available_models"] = available if available.is_a?(Array) && available.any?

      { BEDROCK_KEY => block }
    end

    # Long-term access keys only. A pair accompanied by AWS_SESSION_TOKEN is a temporary
    # STS session — storing it would hand the next session credentials that already expired,
    # which fails in exactly the opaque way Bedrock errors do. Better to have no connection
    # (preflight then says so) than a stale one.
    def static_credentials_from(env)
      return {} if env["AWS_SESSION_TOKEN"].present?
      return {} if env["AWS_ACCESS_KEY_ID"].blank? || env["AWS_SECRET_ACCESS_KEY"].blank?

      { "access_key_id" => env["AWS_ACCESS_KEY_ID"], "secret_access_key" => env["AWS_SECRET_ACCESS_KEY"] }
    end

    def conflicting_env_keys(credentials)
      bedrock_block(credentials) ? BEDROCK_CONFLICTING_ENV : []
    end

    # Lists what this connection can actually invoke. Only an Identity Center connection can
    # be asked: a key entered in the CLI wizard is injected straight into the container and
    # never reaches us in a form we can sign a control-plane call with, so those fall back to
    # the static list.
    #
    # Failure is never fatal — a permission set without bedrock:ListInferenceProfiles is
    # common, and a model picker is not worth breaking a page over.
    def bedrock_available_models(credentials, credential)
      block = bedrock_block(credentials)
      return [] if block.nil? || credential&.user.nil?
      return [] if block["identity_center"].blank?

      vended = CloudAuth::AwsCredentialVendor.new(user: credential.user).call
      profiles = CloudAuth::AwsModelCatalog.new(
        region: block["region"],
        access_key_id: vended.access_key_id,
        secret_access_key: vended.secret_access_key,
        session_token: vended.session_token
      ).inference_profiles

      usable_bedrock_profiles(profiles).map do |profile|
        { model_id: profile.model_id, display_name: profile.name, description: profile.description }
      end
    rescue CloudAuth::Error => e
      Rails.logger.warn("[ClaudeCodeAdapter] Bedrock model list unavailable: #{e.message}")
      []
    end

    # Cheapest and broadest first. A global inference profile costs about 10% less than the
    # regional one for the same model and draws on a much larger capacity pool, so it is the
    # right default — but an organisation with data-residency rules can SCP-block `global`,
    # and then only the regional profile works.
    GEO_PREFERENCE = %w[global us eu apac jp].freeze

    # Bedrock only. An account's catalogue is a long historical list — 25 profiles for one
    # account here, including Claude 3.x (a 2x extended-access surcharge, retiring on its own
    # calendar) and the same models listed once per geography. Newest first, legacy dropped,
    # one geography per model, so the obvious pick is also the right one.
    def usable_bedrock_profiles(profiles)
      candidates = profiles.select { |p| p.anthropic? && !p.legacy? }
      # Application profiles are the account's own objects, not geographic variants of a
      # shared model, so they are never collapsed into each other.
      application, system = candidates.partition(&:application?)

      preferred = system.group_by(&:model_key).map { |_key, group| cheapest_geo(group) }
      (application + preferred).sort_by { |p| [ -p.generation[0], -p.generation[1], p.model_id.to_s ] }
    end

    # Falls through to whatever the account has when the preferred geography is absent, so a
    # model offered only regionally is still offered.
    def cheapest_geo(group)
      group.min_by { |p| [ GEO_PREFERENCE.index(p.geo) || GEO_PREFERENCE.size, p.model_id.to_s ] }
    end

    def bedrock_block(credentials)
      block = credentials.is_a?(Hash) ? credentials[BEDROCK_KEY] : nil
      block.is_a?(Hash) && block["region"].present? ? block : nil
    end

    def bedrock_settings_env(bedrock)
      env = {
        "CLAUDE_CODE_USE_BEDROCK" => "1",
        # Set explicitly rather than relying on the profile's region.
        "AWS_REGION" => bedrock["region"],
        "CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS" =>
          (bedrock["chain_resolve_timeout_ms"] || BEDROCK_CHAIN_RESOLVE_TIMEOUT_MS).to_s
      }
      env["AWS_PROFILE"] = bedrock["profile"] if bedrock["profile"].present?
      env["AWS_BEARER_TOKEN_BEDROCK"] = bedrock["bearer_token"] if bedrock["bearer_token"].present?

      # Long-term access keys the user configured in the wizard. Restored so the next session
      # starts authenticated instead of dropping them back into the login flow.
      static = bedrock["static_credentials"]
      if static.is_a?(Hash) && static["access_key_id"].present?
        env["AWS_ACCESS_KEY_ID"] = static["access_key_id"]
        env["AWS_SECRET_ACCESS_KEY"] = static["secret_access_key"]
      end

      (bedrock["models"] || {}).each do |model_alias, model_id|
        key = BEDROCK_MODEL_ENV[model_alias.to_s]
        env[key] = model_id if key && model_id.present?
      end

      guardrail = bedrock["guardrail"]
      if guardrail.is_a?(Hash) && guardrail["identifier"].present?
        env["ANTHROPIC_CUSTOM_HEADERS"] = [
          "X-Amzn-Bedrock-GuardrailIdentifier: #{guardrail['identifier']}",
          "X-Amzn-Bedrock-GuardrailVersion: #{guardrail['version'] || 1}"
        ].join("\n")
      end

      env
    end

    # The native Bedrock setup wizard lists profiles by scanning the process HOME for
    # [profile ...] sections and IGNORES AWS_CONFIG_FILE, so this has to land at the
    # literal $HOME/.aws/config or the profile is silently absent from the picker.
    def aws_config_file(bedrock)
      profile = bedrock["profile"]
      return {} if profile.blank?

      sso = bedrock["sso_session"]
      sso = nil unless sso.is_a?(Hash) && sso["start_url"].present?
      sections = []

      if sso
        sections << [
          "[sso-session #{profile}]",
          "sso_start_url = #{sso['start_url']}",
          "sso_region = #{sso['region'].presence || bedrock['region']}",
          # Required, or Identity Center returns no refresh token.
          "sso_registration_scopes = sso:account:access"
        ].join("\n")
      end

      lines = [ "[profile #{profile}]" ]
      if sso
        lines << "sso_session = #{profile}"
        lines << "sso_account_id = #{sso['account_id']}" if sso["account_id"].present?
        lines << "sso_role_name = #{sso['role_name']}" if sso["role_name"].present?
      end
      lines << "credential_process = #{bedrock['credential_process']}" if bedrock["credential_process"].present?
      lines << "region = #{bedrock['region']}"
      sections << lines.join("\n")

      { "#{home_dir}/.aws/config" => "#{sections.join("\n\n")}\n" }
    end

    # Session command for agent terminal.
    # Both modes use full Claude TUI to preserve streamed terminal UX.
    def session_command(mode:, prompt: nil, model: nil)
      model ? "claude --model #{Shellwords.shellescape(model)}" : "claude"
    end

    # Context file: ~/.claude/CLAUDE.md (auto-read by Claude Code at startup)
    def context_file_path
      "#{home_dir}/.claude/CLAUDE.md"
    end

    def skills_agent_name
      "claude-code"
    end

    # MCP config: /workspace/.mcp.json
    # Claude Code supports: "http" (streamable-http), "sse" (deprecated), "stdio"
    # See: https://code.claude.com/docs/en/mcp
    def mcp_config(servers)
      mcp_servers = {}
      servers.each do |s|
        entry = { "type" => mcp_transport_type(s.transport) }
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args)
          entry["env"] = mcp_stdio_env(s)
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[MCPServer.config_key_for(s.name)] = entry
      end
      { "/workspace/.mcp.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    # Fetch available models from Anthropic API.
    # Requires API key auth (OAuth accounts may not have access).
    ANTHROPIC_MODELS_URL = "https://api.anthropic.com/v1/models"

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    # Fetch the model list using whichever auth the credential carries:
    #   - primaryApiKey            → x-api-key (platform.claude.com API key path)
    #   - claudeAiOauth.accessToken → Authorization: Bearer + oauth beta header (claude.ai OAuth path)
    # OAuth support matters because claude.ai logins have no API key, so without
    # it those users would always fall back to the hardcoded (stale) list.
    def fetch_available_models_with_source(credentials, credential: nil)
      # A Bedrock connection has no Anthropic-side token to ask, and its real catalogue is
      # account-specific: enterprise deployments expose models as application inference
      # profiles whose ARNs no static list can name.
      bedrock_models = bedrock_available_models(credentials, credential)
      return { models: bedrock_models, source: :api } if bedrock_models.present?

      api_key = credentials["primaryApiKey"]
      oauth_token = credentials.dig("claudeAiOauth", "accessToken")

      models =
        if api_key.present?
          fetch_models_via_api(api_key: api_key)
        elsif oauth_token.present?
          fetch_models_via_api(oauth_token: oauth_token)
        else
          []
        end

      if models.present?
        { models: models, source: :api }
      else
        { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
      end
    rescue StandardError => e
      Rails.logger.warn("[ClaudeCodeAdapter] fetch_available_models failed: #{e.message}")
      { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
    end

    # Safety net used only when the live API is unreachable or the token lacks
    # model-list access. Kept current so even the fallback isn't badly stale.
    FALLBACK_CLAUDE_MODELS = [
      { model_id: "claude-opus-4-8", display_name: "Claude Opus 4.8", description: "Most capable model" },
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", description: "Best balance of speed and intelligence" },
      { model_id: "claude-opus-4-7", display_name: "Claude Opus 4.7", description: "Highly autonomous, long-horizon work" },
      { model_id: "claude-opus-4-6", display_name: "Claude Opus 4.6", description: "Advanced reasoning" },
      { model_id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5", description: "Fastest model" }
    ].freeze

    # Default environment variables for Claude Code runtime.
    def default_env_vars(session)
      route_token = session.route_token
      resource_attributes = "terminal_session_token=#{route_token}"

      {
        # MITM proxy — intercept Anthropic API traffic
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => "api.anthropic.com",
        # OTLP telemetry
        "CLAUDE_CODE_ENABLE_TELEMETRY" => "1",
        "OTEL_EXPORTER_OTLP_ENDPOINT" => Settings.otel.endpoint,
        "OTEL_EXPORTER_OTLP_PROTOCOL" => "http/protobuf",
        "OTEL_METRICS_EXPORTER" => "otlp",
        "OTEL_METRIC_EXPORT_INTERVAL" => "2000",
        "OTEL_RESOURCE_ATTRIBUTES" => resource_attributes,
        # MCP server startup timeout (ms). Default 90s — stdio servers need time for pipx/npx cold start.
        "MCP_TIMEOUT" => Settings.agents.mcp.startup_timeout_ms.to_s
      }.merge(cloud_credential_env(session)).compact
    end

    # Only a session that actually vends gets a vending key. These go in process env
    # rather than the settings file because the helper is spawned by the AWS SDK, not by
    # Claude Code, and must work regardless of which process resolves credentials.
    def cloud_credential_env(session)
      block = bedrock_block(session.user&.agent_credentials&.find_by(agent_type: "claude_code")&.config_data || {})
      connected = block.present? && block["credential_process"].present?
      # An auth container gets the vending env even with no connection: reporting that
      # none exists is the helper's whole job there.
      return {} unless connected || session.session_type == "auth_setup"

      {
        "AIXLE_CLOUD_CREDENTIALS_URL" => Settings.cloud.credentials_url,
        "AIXLE_CLOUD_KEY" => CloudAuth::SessionKey.generate(session)
      }
    end

    # Parse OTLP payload, collect events, and persist usage statistics.
    # Each OTLP batch (delta) becomes one event with token breakdown.
    def ingest_usage(payload, terminal_session)
      new_events = extract_events_from_otlp(payload, terminal_session.route_token)
      return :accepted if new_events.empty?

      UsageStatistic.transaction do
        stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic(
          tokens: 0, cost_cents: 0, input_tokens: 0, output_tokens: 0,
          cache_write_tokens: 0, cache_read_tokens: 0, source: "otlp",
          events_count: 0, events_data: []
        )

        all_events = (stat.events_data || []) + new_events
        totals = aggregate_events(all_events)
        models = all_events.filter_map { |e| e["model"] }.uniq

        stat.assign_attributes(
          input_tokens: totals[:input_tokens],
          output_tokens: totals[:output_tokens],
          cache_write_tokens: totals[:cache_write_tokens],
          cache_read_tokens: totals[:cache_read_tokens],
          total_cents_precise: totals[:total_cents],
          cost_cents: totals[:total_cents].ceil,
          models: models,
          source: "otlp",
          events_count: all_events.size,
          events_data: all_events
        )
        stat.save!
      end

      :ok
    end

    private

    # Base-login client id, from Settings when configured, else the known public id.
    def base_oauth_client_id
      Settings.agents.oauth&.base_client_id.presence || BASE_OAUTH_CLIENT_ID
    rescue StandardError
      BASE_OAUTH_CLIENT_ID
    end

    # Exchange a refresh token for a fresh OAuth block via the token endpoint.
    # Returns the rebuilt block (accessToken/refreshToken/expiresAt/scopes/clientId),
    # or nil on any network / non-2xx / parse failure (logged). Preserves the block's
    # refreshToken when the server omits a rotated one, and its clientId (designOauth
    # carries its own; claudeAiOauth's is typically nil and dropped by .compact).
    def request_oauth_refresh(client_id:, refresh_token:, previous:, now_ms:)
      uri = URI(OAUTH_TOKEN_URL)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type:    "refresh_token",
        client_id:     client_id,
        refresh_token: refresh_token
      )
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[ClaudeCodeAdapter] Token refresh failed: #{response.code} #{response.body.to_s.truncate(200)}")
        return nil
      end
      data = JSON.parse(response.body)
      {
        "accessToken"  => data["access_token"],
        "refreshToken" => data["refresh_token"].presence || refresh_token, # rotation: keep old if server omits
        "expiresAt"    => now_ms + (data["expires_in"].to_i * 1000),
        "scopes"       => (data["scope"].present? ? data["scope"].split(" ") : previous["scopes"]),
        "clientId"     => previous["clientId"] # preserve (designOauth carries its own; claudeAiOauth may be nil → compacted)
      }.compact
    rescue StandardError => e
      Rails.logger.warn("[ClaudeCodeAdapter] Token refresh error: #{e.class}: #{e.message}")
      nil
    end

    # Keep whichever OAuth block has the later expiry; never drop one that only the
    # stored blob has (the incoming session may simply not have touched that scope).
    def freshest_oauth_block(current_block, incoming_block)
      return incoming_block if current_block.blank?
      return current_block if incoming_block.blank?

      incoming_block["expiresAt"].to_i >= current_block["expiresAt"].to_i ? incoming_block : current_block
    end

    # Returns an array of normalized models, or [] on any non-success / empty
    # result (the caller decides whether to fall back). Exactly one of api_key /
    # oauth_token should be provided.
    OAUTH_BETA_HEADER = "oauth-2025-04-20"

    def fetch_models_via_api(api_key: nil, oauth_token: nil)
      uri = URI(ANTHROPIC_MODELS_URL)
      uri.query = URI.encode_www_form(limit: 100)
      req = Net::HTTP::Get.new(uri)
      req["anthropic-version"] = "2023-06-01"

      if api_key.present?
        req["x-api-key"] = api_key
      elsif oauth_token.present?
        # OAuth tokens authenticate via Bearer + the oauth beta header (not x-api-key).
        req["authorization"] = "Bearer #{oauth_token}"
        req["anthropic-beta"] = OAUTH_BETA_HEADER
      else
        return []
      end

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      (data["data"] || []).filter_map do |m|
        next unless m["id"].to_s.include?("claude")

        { model_id: m["id"], display_name: m["display_name"] || m["id"], description: "#{m["max_input_tokens"]} max input tokens" }
      end
    end

    # Build normalized events from OTLP payload (same format as Cursor API events).
    def extract_events_from_otlp(payload, terminal_session_token)
      events = []
      return events if terminal_session_token.blank?

      (payload["resourceMetrics"] || []).each do |rm|
        resource_attrs = rm.dig("resource", "attributes") || []

        (rm["scopeMetrics"] || []).each do |sm|
          token_breakdown = {}
          cost_usd = 0.0
          model = nil
          timestamp_ns = nil

          (sm["metrics"] || []).each do |metric|
            name = normalize_metric_name(metric["name"].to_s)
            next if name.blank?

            extract_data_points(metric).each do |dp|
              token = extract_terminal_session_token(dp["attributes"] || [], resource_attrs)
              next if token != terminal_session_token

              value = number_from_data_point(dp)
              next if value.nil?

              dp_attrs = dp["attributes"] || []
              model ||= attribute_value(dp_attrs, "model")
              timestamp_ns ||= dp["timeUnixNano"]

              case name
              when METRIC_TOKENS_NAME
                type = attribute_value(dp_attrs, "type") || "unknown"
                token_breakdown[type] = (token_breakdown[type] || 0) + value.to_i
              when METRIC_COST_NAME
                cost_usd += value.to_f
              end
            end
          end

          next if token_breakdown.values.sum.zero? && cost_usd.zero?

          events << {
            "model" => model,
            "timestamp" => timestamp_ns ? (timestamp_ns.to_i / 1_000_000).to_s : nil,
            "tokenUsage" => {
              "inputTokens" => token_breakdown["input"] || 0,
              "outputTokens" => token_breakdown["output"] || 0,
              "cacheReadTokens" => token_breakdown["cacheRead"] || 0,
              "cacheWriteTokens" => token_breakdown["cacheCreation"] || 0,
              "totalCents" => (cost_usd * 100).round(6)
            },
            "source" => "otlp"
          }
        end
      end

      events
    end

    def aggregate_events(events)
      events.each_with_object(
        { input_tokens: 0, output_tokens: 0, cache_write_tokens: 0,
          cache_read_tokens: 0, total_cents: 0.0 }
      ) do |event, totals|
        usage = event["tokenUsage"] || {}
        totals[:input_tokens] += usage["inputTokens"].to_i
        totals[:output_tokens] += usage["outputTokens"].to_i
        totals[:cache_write_tokens] += usage["cacheWriteTokens"].to_i
        totals[:cache_read_tokens] += usage["cacheReadTokens"].to_i
        totals[:total_cents] += usage["totalCents"].to_f
      end
    end

    def normalize_metric_name(name)
      return name if name == METRIC_TOKENS_NAME || name == METRIC_COST_NAME

      LEGACY_METRIC_NAMES[name]
    end

    def extract_data_points(metric)
      sum = metric["sum"]
      return sum["dataPoints"] if sum.is_a?(Hash) && sum["dataPoints"].is_a?(Array)

      gauge = metric["gauge"]
      return gauge["dataPoints"] if gauge.is_a?(Hash) && gauge["dataPoints"].is_a?(Array)

      []
    end

    def extract_terminal_session_token(attrs, resource_attrs)
      value = attribute_value(attrs, "terminal_session_token")
      value ||= attribute_value(resource_attrs, "terminal_session_token")

      normalize_terminal_session_token(value)
    end

    def attribute_value(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["stringValue"].to_s if value.key?("stringValue")
        return value["intValue"].to_s if value.key?("intValue")
      end

      nil
    end

    def normalize_terminal_session_token(raw)
      token = raw.to_s.strip
      return nil if token.blank?

      token
    end

    def number_from_data_point(data_point)
      if data_point.key?("asInt")
        data_point["asInt"].to_f
      elsif data_point.key?("asDouble")
        data_point["asDouble"].to_f
      end
    end

    def dollars_to_cents(value)
      (value.to_f * 100).round
    end

    # Map internal transport name to Claude Code MCP type
    def mcp_transport_type(transport)
      case transport.to_s
      when "streamable-http", "http" then "http"
      when "sse"                     then "sse"
      else "stdio"
      end
    end

    # Permission mode is always bypassPermissions. Both interactive and
    # non_interactive sessions run headless in a sandbox container, so there is
    # nobody to answer a permission prompt. "auto" and "dontAsk" both still block
    # or deny tools that need a scope grant (e.g. DesignSync — "Permission to use
    # DesignSync has been denied because Claude Code is running in don't ask mode").
    # bypassPermissions never prompts/denies; the startup warning is pre-accepted
    # via skipDangerousModePermissionPrompt (see generate_settings).
    PERMISSION_DEFAULT_MODE = "bypassPermissions"

    def generate_settings(mcp_server_names = [], model: nil, bedrock: nil)
      settings = {
        "permissions" => {
          "defaultMode" => PERMISSION_DEFAULT_MODE,
          "allow" => allowed_tools(mcp_server_names),
          "deny" => [],
          "ask" => []
        },
        # Pre-accept the "Bypass Permissions mode" startup warning so a headless
        # container session never blocks on it. The operative key is
        # skipDangerousModePermissionPrompt — it is exactly what Claude Code writes
        # to settings.json when a user clicks through the warning once.
        # bypassPermissionsWarningAccepted alone does NOT suppress the prompt.
        "bypassPermissionsWarningAccepted" => true,
        "skipDangerousModePermissionPrompt" => true,
        "enableAllProjectMcpServers" => true,
        "env" => {
          "MCP_TIMEOUT" => Settings.agents.mcp.startup_timeout_ms.to_s
        }
      }
      settings["model"] = model if model.present?

      if bedrock
        settings["env"] = settings["env"].merge(bedrock_settings_env(bedrock))
        available = bedrock["available_models"]
        settings["availableModels"] = available if available.is_a?(Array) && available.any?
        # Only awsAuthRefresh renders its output to the user (an "Authentication" panel),
        # and only while the command is still running — so a browser-based re-auth must
        # print its URL and then block. It fires only when credentials are already
        # invalid, and must exit non-zero rather than retry (a retrying command loops
        # forever behind a proxy that interrupts the browser flow).
        refresh = bedrock["auth_refresh_command"]
        settings["awsAuthRefresh"] = refresh if refresh.present?
      end

      settings
    end

    def generate_projects_config(workflow_config)
      mcp_names = workflow_config[:enabled_mcp_servers] || []
      {
        "/workspace" => {
          # Tools and MCP from workflow config
          "allowedTools" => allowed_tools(mcp_names),
          "mcpServers" => workflow_config[:mcp_servers] || {},
          "mcpContextUris" => workflow_config[:mcp_context_uris] || [],
          "enabledMcpjsonServers" => workflow_config[:enabled_mcp_servers] || [],
          "disabledMcpjsonServers" => workflow_config[:disabled_mcp_servers] || [],

          # Always trust workspace (skip dialog)
          "hasTrustDialogAccepted" => true,
          "projectOnboardingSeenCount" => 1,

          # External includes (security)
          "hasClaudeMdExternalIncludesApproved" => false,
          "hasClaudeMdExternalIncludesWarningShown" => false,

          # Vulnerability cache (will be populated at runtime)
          "reactVulnerabilityCache" => {
            "detected" => false,
            "package" => nil,
            "packageName" => nil,
            "version" => nil,
            "packageManager" => nil
          }
        }
      }
    end
  end
end
