# frozen_string_literal: true

require "base64"

module Agents
  # Base adapter interface for agent-specific credential handling
  # Each agent (Claude Code, Cursor CLI, etc.) has different config formats and paths
  class BaseAdapter
    # Path to main config file inside container
    # @return [String]
    def config_path
      raise NotImplementedError, "#{self.class} must implement #config_path"
    end

    # Home directory inside container
    # @return [String]
    def home_dir
      raise NotImplementedError, "#{self.class} must implement #home_dir"
    end

    # Default config file paths for UI hints (path => description)
    # @return [Array<String>]
    def self.default_config_paths
      []
    end

    # Path to watch for auth completion (for watcher service)
    # @return [String]
    def auth_watch_path
      config_path
    end

    # Config files to write before auth starts (no credentials needed).
    # Used by AgentAuthStrategy#before_exec.
    # @return [Hash<String, String>] path => content
    def auth_setup_files
      {}
    end

    # Keys to check for auth completion (any key present = auth complete)
    # Supports nested keys like "oauthAccount.accountUuid"
    # @return [Array<String>]
    def auth_required_keys
      raise NotImplementedError, "#{self.class} must implement #auth_required_keys"
    end

    # Check if authentication is complete based on config content
    # @param config_content [String] raw config file content
    # @return [Boolean]
    def auth_complete?(config_content)
      raise NotImplementedError, "#{self.class} must implement #auth_complete?"
    end

    # ---- Auth-kind hooks -------------------------------------------------------
    # An auth session can run in different "kinds" (default "agent" = a fresh
    # login). AgentAuthStrategy is generic and drives everything through these
    # hooks; adapters that support extra kinds (e.g. Claude's "design") override
    # them. Defaults are kind-agnostic so no other adapter needs to change.

    # Files to seed into the container before the CLI launches, for `kind`, given
    # the user's currently-stored credential config. Default: the fresh-login setup
    # files (no credentials).
    def auth_setup_files_for(_kind, _current_config = nil)
      auth_setup_files
    end

    # Keys the watcher waits on for `kind`. Default: the standard login keys.
    def auth_required_keys_for(_kind)
      auth_required_keys
    end

    # Completion predicate for `kind`. Default: the standard auth_complete?.
    def auth_complete_for?(_kind, config_content)
      auth_complete?(config_content)
    end

    # Commands to launch/drive the CLI for `kind`, sent into the tmux session AFTER
    # the setup files are written. Empty (default) = the entrypoint's TTYD_CMD
    # launches the CLI at container start (a fresh login). Non-empty = the strategy
    # starts `bash` and sends these instead (so the CLI starts with seeded creds).
    def auth_launch_commands_for(_kind)
      []
    end

    # Reconcile the credentials scraped from the container (`captured`) with the
    # user's currently-stored credential (`current`) for `kind`, returning the blob to
    # persist. Default: replace with the freshly-scraped set (a normal login should
    # supersede whatever was there). A kind that only LAYERS onto an existing login
    # (e.g. Claude's "design") overrides this to add just its own block, so it never
    # re-captures/duplicates the base login it seeded into the container.
    def reconcile_captured_credentials(_kind, _current, captured)
      captured
    end

    # Extract credentials from config content (only fields we need to persist)
    # @param config_content [String] raw config file content
    # @return [Hash] credentials to store in database
    def extract_credentials(config_content)
      raise NotImplementedError, "#{self.class} must implement #extract_credentials"
    end

    # Generate full config file content for a new container
    # @param credentials [Hash] stored credentials from database
    # @param workflow_config [Hash] optional workflow-specific settings (tools, MCP, etc.)
    # @return [Hash] full config to write to container
    def generate_config(credentials, workflow_config = {})
      raise NotImplementedError, "#{self.class} must implement #generate_config"
    end

    # List of config files to write to container (path => content)
    # Override if agent needs multiple config files
    # @param credentials [Hash] stored credentials from database
    # @param workflow_config [Hash] optional workflow-specific settings
    # @return [Hash<String, String>] path => content mapping
    def config_files(credentials, workflow_config = {})
      {
        config_path => generate_config(credentials, workflow_config).to_json
      }
    end

    # UID of the container user (used for file ownership in tar headers)
    # @return [Integer]
    def container_uid
      1001
    end

    # =================================================================
    # Session Command (mode-aware CLI command for ttyd)
    # =================================================================

    # Generate CLI command for the session based on mode.
    # @param mode [String] "interactive" or "non_interactive"
    # @param prompt [String, nil] initial prompt for non_interactive mode
    # @param model [String, nil] requested model ID (nil = runtime default)
    # @return [String] CLI command string
    def session_command(mode:, prompt: nil, model: nil)
      raise NotImplementedError, "#{self.class} must implement #session_command"
    end

    # =================================================================
    # Context File (CLI-specific instruction file auto-read at startup)
    # =================================================================

    # Path to CLI-specific context file (auto-read by CLI at startup).
    # Written to home dir (not workspace) to keep /workspace clean.
    # @return [String, nil] nil if CLI doesn't support context files
    def context_file_path
      nil
    end

    # =================================================================
    # Skill Installation (via npx skills add)
    # Skills are installed globally using the skills.sh CLI tool.
    # =================================================================

    # Whether skills are embedded directly into the context file (AGENTS.md).
    # When true, npx skills add is skipped and skills are merged into context.
    # @return [Boolean]
    def includes_skills_in_context?
      false
    end

    # Agent name for `npx skills add --agent <name>`.
    # Maps to the skills.sh ecosystem agent identifiers.
    # @return [String]
    def skills_agent_name
      raise NotImplementedError, "#{self.class} must implement #skills_agent_name"
    end

    # =================================================================
    # MCP Server Configuration
    # Each CLI has different MCP config format and file path
    # =================================================================

    # Generate MCP config files for this CLI.
    # @param servers [Array<OpenStruct>] resolved servers with :name, :url, :transport, :headers
    # @return [Hash<String, String>] { path => content }
    def mcp_config(servers)
      {}
    end

    # How to handle existing file at MCP config path.
    # :fresh       — write new file (Claude, Cursor)
    # :merge_json  — read existing JSON, merge mcpServers key, write back (Gemini)
    # :append_toml — read existing TOML, append MCP section (Codex)
    # @return [Symbol]
    def mcp_merge_strategy
      :fresh
    end

    # Baseline environment variables that every STDIO MCP subprocess must receive,
    # regardless of whether the launching agent CLI forwards the container's
    # environment to the servers it spawns.
    #
    # The Playwright MCP resolves its baked browser through PLAYWRIGHT_BROWSERS_PATH
    # (set to /opt/playwright-browsers as an ENV in docker/base/Dockerfile). Claude
    # Code forwards the full parent environment to STDIO MCP servers, so it picks the
    # var up automatically — but Codex (and other CLIs) spawn STDIO servers with a
    # restricted environment that drops custom vars. Without the path the MCP falls
    # back to ~/.cache/ms-playwright, where no browser is baked, and fails with:
    #   Error: Browser "chrome-for-testing" is not installed.
    # Emitting the var explicitly in the MCP config makes the baked browser reachable
    # under every agent CLI (task #340). Unrelated MCP servers ignore it.
    #
    # Keep the value in sync with ENV PLAYWRIGHT_BROWSERS_PATH in docker/base/Dockerfile.
    # The Rails app runs on the host, not inside the agent container, so the path
    # cannot be read from the process environment here — it must be a constant.
    MCP_STDIO_BASE_ENV = { "PLAYWRIGHT_BROWSERS_PATH" => "/opt/playwright-browsers" }.freeze

    # Environment for a STDIO MCP server config entry: the baseline vars every MCP
    # subprocess needs, overlaid with the server's own configured env (the server's
    # values win on conflict). Always returns a non-empty hash.
    # @param server [#env] resolved MCP server
    # @return [Hash<String, String>]
    def mcp_stdio_env(server)
      server_env = server.respond_to?(:env) && server.env.present? ? server.env.to_h : {}
      MCP_STDIO_BASE_ENV.merge(server_env)
    end

    # The Playwright MCP npm package and the exact version baked into the agent
    # base image. Baking the browser and pinning the *global* install is not
    # enough on its own: agents launch the MCP at runtime via `npx @playwright/mcp`,
    # and an unqualified spec lets npx resolve/download a different (newer) release
    # into its cache — whose bundled browser revision can differ from the one baked
    # at build time, re-introducing the "chrome-for-testing is not installed" drift
    # this task fixes (#340). Pinning the version in the *emitted* command keeps the
    # launched MCP locked to the baked browser regardless of npx cache state.
    #
    # Keep PLAYWRIGHT_MCP_VERSION in sync with ARG PLAYWRIGHT_MCP_VERSION in
    # docker/base/Dockerfile. The Rails app runs on the host, not inside the agent
    # container, so the version cannot be read from the image here — it is a constant.
    PLAYWRIGHT_MCP_PACKAGE = "@playwright/mcp"
    PLAYWRIGHT_MCP_VERSION = "0.0.78"

    # A STDIO server's command args with the Playwright MCP package spec pinned to
    # PLAYWRIGHT_MCP_VERSION, so the launched MCP cannot float independently of the
    # baked browser. Any arg that is `@playwright/mcp` or `@playwright/mcp@<tag>`
    # (e.g. `@playwright/mcp@latest`) is rewritten to `@playwright/mcp@<version>`;
    # every other arg (and every non-Playwright server) passes through untouched.
    # @param server [#args] resolved MCP server
    # @return [Array<String>]
    def mcp_stdio_args(server)
      return [] unless server.respond_to?(:args) && server.args.present?

      Array(server.args).map do |arg|
        a = arg.to_s
        if a == PLAYWRIGHT_MCP_PACKAGE || a.start_with?("#{PLAYWRIGHT_MCP_PACKAGE}@")
          "#{PLAYWRIGHT_MCP_PACKAGE}@#{PLAYWRIGHT_MCP_VERSION}"
        else
          a
        end
      end
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # Used for agent-specific config like GOOGLE_CLOUD_PROJECT
    # =================================================================

    # Default environment variables for the container runtime.
    # @param session [TerminalSession, nil]
    # @return [Hash<String, String>]
    def default_env_vars(_session = nil)
      {}
    end

    # Fields that must be configured before starting container
    # Shown in UI before auth terminal starts
    # @return [Array<Hash>] list of field definitions
    # Example: [{ key: 'google_cloud_project', label: 'Google Project ID', required: true }]
    def required_env_fields
      []
    end

    # Extract environment variables from metadata (session or credential)
    # @param metadata [Hash] metadata hash
    # @return [Hash<String, String>] env var name => value
    def env_vars_from_metadata(metadata)
      {}
    end

    # Validate that required env fields are present in metadata
    # @param metadata [Hash] metadata hash
    # @return [Array<String>] list of error messages (empty if valid)
    def validate_metadata(metadata)
      missing = required_env_fields
                .select { |f| f[:required] && metadata[f[:key]].blank? }
                .map { |f| "#{f[:label]} is required" }
      missing
    end

    # Check if agent requires env fields before starting
    # @return [Boolean]
    def requires_env_fields?
      required_env_fields.any? { |f| f[:required] }
    end

    # Parse and persist usage statistics for a terminal session.
    # Called on each OTLP trace payload (hooks, native traces).
    # @param payload [Hash] parsed OTLP JSON payload
    # @param terminal_session [TerminalSession]
    # @return [Symbol] :ok when persisted, :accepted when no usage found
    def ingest_usage(_payload, _terminal_session)
      pp _payload
    end

    # =================================================================
    # Available Models (fetched from provider API)
    # =================================================================

    # Fetch available models from the provider API using user credentials.
    # @param credentials [Hash] decrypted credential data from AgentCredential
    # @param credential [AgentCredential, nil] optional record for token refresh
    # @return [Array<Hash>] normalized models: [{ model_id:, display_name:, description: }]
    def fetch_available_models(_credentials, credential: nil)
      []
    end

    # Fetch models with source indicator for cache decisions.
    # @return [Hash{ models: Array<Hash>, source: Symbol }] source is :api or :fallback
    def fetch_available_models_with_source(credentials, credential: nil)
      { models: fetch_available_models(credentials, credential: credential), source: :api }
    end

    # Comparable expiry of the credential's primary token, or nil if the agent's
    # tokens don't carry one. Used to avoid overwriting a newer stored token with
    # an older one when sessions run concurrently and refresh-token rotation occurs.
    # @param credentials [Hash] decrypted credential data
    # @return [Integer, nil]
    def token_expires_at(_credentials)
      nil
    end

    # Decode the `exp` claim (seconds since epoch) from a JWT payload WITHOUT
    # verifying the signature, returning epoch milliseconds — or nil when the
    # value is not a three-segment JWT or carries no `exp`. Adapters whose access
    # tokens are JWTs (Codex, Cursor) use this to implement #token_expires_at so
    # the proactive-refresh sweep can select them.
    # @param token [String, nil]
    # @return [Integer, nil]
    def jwt_exp_ms(token)
      return nil if token.blank?

      segments = token.split(".")
      return nil unless segments.size == 3

      payload = JSON.parse(Base64.urlsafe_decode64(base64_pad(segments[1])))
      exp = payload["exp"]
      exp.present? ? exp.to_i * 1000 : nil
    rescue StandardError
      nil
    end

    # Merge freshly-collected credentials (from a live session's container) onto the
    # stored blob before persisting. Default: replace wholesale, but keep the stored
    # blob when the incoming token is older (refresh-token rotation guard). Adapters
    # whose credentials hold multiple independently-rotating token blocks override this
    # to merge per block.
    # @param current [Hash] currently-stored credential data
    # @param incoming [Hash] credentials collected from the session container
    # @return [Hash] the blob to persist
    def merge_refreshed_credentials(current, incoming)
      new_exp = token_expires_at(incoming)
      old_exp = token_expires_at(current)
      return current if new_exp && old_exp && new_exp.to_i <= old_exp.to_i

      incoming
    end

    # Proactively refresh this credential's OAuth token(s) server-side, persisting
    # any rotated tokens back onto the AgentCredential. Called by the Temporal
    # token-refresh sweep for credentials nearing expiry. Default: no-op (agents
    # whose credentials don't carry a refreshable OAuth token).
    #
    # MUST persist via credential.with_lock + merge_refreshed_credentials +
    # AgentCredential.from_artifacts (never a bare update! of a whole blob) so a
    # concurrent live session's cleanup can't race the read-merge-write.
    #
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :not_needed | :error, detail: String | nil }
    def refresh!(_credential)
      { status: :not_needed, detail: nil }
    end

    # Persist a freshly-refreshed credential blob under a row lock, guarding
    # against clobbering a concurrently-rotated (newer) token. Mirrors the Claude
    # per-block pattern for single-block agents (Codex, Cursor): reload the locked
    # row, run it through merge_refreshed_credentials (rotation guard), and write
    # via AgentCredential.from_artifacts. NEVER bare-update! a whole blob — a
    # concurrent live session's cleanup can otherwise race the read-merge-write.
    # @param credential [AgentCredential]
    # @param new_config [Hash] the freshly-refreshed credential blob
    # @return [Hash] the blob actually persisted (may be the pre-existing one if it
    #   was newer)
    def persist_refreshed!(credential, new_config)
      credential.with_lock do
        current = credential.config_data
        merged  = merge_refreshed_credentials(current, new_config)
        AgentCredential.from_artifacts(credential.user_id, credential.company_id, credential.agent_type, merged) if merged != current
        merged
      end
    end

    # =================================================================
    # Usage Collection (called once at session cleanup)
    # =================================================================

    # Domains tracked by MITM proxy for usage logging.
    # Empty = log all traffic (default for agents without usage tracking).
    # @return [Array<String>]
    def mitm_tracked_domains
      []
    end

    # Log files inside container to collect as artifacts after session ends.
    # @return [Array<String>]
    def session_log_paths
      %w[/var/log/context.log]
    end

    # Collect and verify usage data at session cleanup.
    # Called from AgentSessionStrategy#before_cleanup after artifact collection.
    # @param terminal_session [TerminalSession]
    # @param artifacts [Hash<String, String>] collected artifacts (path => content)
    def collect_usage(_terminal_session, _artifacts = {})
      # No-op by default. Override in adapters with usage tracking.
    end

    protected

    def parse_json(content)
      JSON.parse(content)
    rescue JSON::ParserError
      {}
    end

    # Right-pad a base64url segment to a multiple of 4 so Base64.urlsafe_decode64
    # (which is strict about padding) accepts a JWT payload segment.
    def base64_pad(str)
      str + ("=" * ((4 - (str.length % 4)) % 4))
    end
  end
end
