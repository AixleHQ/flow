# frozen_string_literal: true

require "base64"
require "shellwords"

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

    # Every file that has to be read back out of a container to reconstruct this
    # credential. Codex is the one runtime whose auth lives in a single file and nothing
    # else, which is why the default is that file; every other adapter overrides.
    # @return [Array<String>]
    def auth_file_paths
      [ config_path ]
    end

    # The files that carry token material, and ONLY those. #config_files renders the whole
    # container configuration — settings, MCP wiring, model pins — from a workflow_config
    # that a mid-session token delivery does not have, so re-rendering it would overwrite a
    # running session's configuration with defaults. This is the narrow counterpart used
    # when the only thing that changed is the token (Agents::CredentialDelivery).
    # @param credentials [Hash] decrypted credential data
    # @return [Hash] path => content
    def credential_files(credentials)
      { config_path => generate_config(credentials).to_json }
    end

    # UID of the container user (used for file ownership in tar headers)
    # @return [Integer]
    def container_uid
      1001
    end

    # =================================================================
    # Session Command (mode-aware CLI command for ttyd)
    # =================================================================

    # The command that starts the CLI, without the prompt: for a non_interactive
    # session AgentSessionStrategy appends the prompt as the last argument, read from
    # a file in the container. `mode` is for the flags a runtime needs to take it.
    # @param mode [String] "interactive" or "non_interactive"
    # @param model [String, nil] requested model ID (nil = runtime default)
    # @return [String] CLI command string
    def session_command(mode:, model: nil)
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

    # Directory the skills CLI installs global skills into for this runtime, i.e.
    # where `skills add -g -a <agent>` puts them. Hand-written skills are written
    # here directly so they land exactly where installed ones do — the CLI is not
    # used for them, because it reports the skill's files to skills.sh as telemetry
    # and a hand-written skill may be private.
    #
    # @return [String, nil] nil when the runtime has no such directory, in which
    #   case a manual skill can only reach it through the context file.
    def skills_install_path
      nil
    end

    # =================================================================
    # MCP Server Configuration
    # Each CLI has different MCP config format and file path
    # =================================================================

    # Generate MCP config files for this CLI.
    # @param servers [Array<OpenStruct>] resolved servers with :name, :url, :transport, :headers
    # @return [Hash<String, String>] { path => content }
    def mcp_config(_servers)
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

    # Env keys that must NOT reach the container given this credential's active provider
    # config, because the CLI would silently prefer them over what we configured.
    # Filtered by AgentSessionStrategy after every other env source has been merged.
    # @param _credentials [Hash] the credential's config_data
    # @return [Array<String>]
    def conflicting_env_keys(_credentials)
      []
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
    def env_vars_from_metadata(_metadata)
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
      :accepted
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

    # Plan-usage windows for a credential whose auth is a consumer subscription
    # rather than metered API billing — how much of a rolling quota has been
    # burned and when it resets. nil means "this credential has no such windows":
    # an API key or a cloud-provider connection bills per token, and most agents
    # have no equivalent concept at all.
    # @param _credentials [Hash] decrypted credential data from AgentCredential
    # @return [Hash, nil] { status:, windows: [{ key:, utilization:, resets_at: }], ... }
    def fetch_subscription_usage(_credentials)
      nil
    end

    # Model ids a stored default may still carry after the vendor retired them,
    # mapped to the replacement to run instead. A retired id is not "an older
    # model" — the vendor answers 404, so every session started from that pin
    # fails. Adapters whose vendor retires ids override this.
    RETIRED_MODEL_REPLACEMENTS = {}.freeze

    # The model id to actually use for a stored default: the stored value unless
    # it names a retired model, in which case its replacement. Unknown ids pass
    # through untouched — an id we don't recognise is far more likely to be a
    # per-account one (a Bedrock inference-profile ARN, a preview slug) than a
    # dead one, and rewriting it would break the pin it is meant to protect.
    # @param model_id [String, nil]
    # @return [String, nil]
    def migrate_model_id(model_id)
      return model_id if model_id.blank?

      self.class::RETIRED_MODEL_REPLACEMENTS.fetch(model_id, model_id)
    end

    # Normalise an expiry to epoch milliseconds, which is what #token_expires_at
    # returns and what AgentCredential#sync_expires_at divides back down. Vendors
    # write the same fact three different ways — an ISO8601 string (Antigravity's
    # `expiry`, Kiro's `expires_at`), epoch seconds, or already-milliseconds — and an
    # adapter should not have to care which. Anything unparseable is nil, i.e. "no
    # expiry known", which leaves the credential permanently active rather than
    # killing it on a formatting surprise.
    # @param value [String, Numeric, nil]
    # @return [Integer, nil]
    def expiry_ms(value)
      return nil if value.blank?

      case value
      when Numeric, /\A\d+\z/
        seconds_or_ms = value.to_i
        # An epoch in seconds is ~1.7e9; the same instant in milliseconds is ~1.7e12.
        seconds_or_ms > 100_000_000_000 ? seconds_or_ms : seconds_or_ms * 1000
      when String
        parsed = Time.zone.parse(value)
        parsed && (parsed.to_f * 1000).round
      end
    rescue ArgumentError, TypeError
      nil
    end

    # Comparable expiry of the credential's primary token, or nil if the agent's
    # tokens don't carry one. Used to avoid overwriting a newer stored token with
    # an older one when sessions run concurrently and refresh-token rotation occurs.
    # @param credentials [Hash] decrypted credential data
    # @return [Integer, nil]
    def token_expires_at(_credentials)
      nil
    end

    # How this runtime's credential lives and dies. One declaration per adapter, read by
    # everything that has to decide something about a token: which runtimes the refresh
    # sweep selects (AgentCredential.refreshable_agent_types is derived from it), whether
    # an expiry is actionable or only informational, and what the user is told when it
    # runs out.
    #
    # It exists because these facts used to be spread across a hardcoded list of agent
    # types, an optional #token_expires_at and an optional #refresh!, with nothing tying
    # them together — so a runtime could ship an expiry with no way to act on it (a
    # working credential painted "expired" an hour after login) or a refresh the sweep
    # could never select (a NULL expiry, which is the cursor_cli population). Both shapes
    # are now rejected by test/services/agents/credential_lifecycle_contract_test.rb.
    #
    # Keys:
    #   expiry   :token  — an expiry is readable from the stored blob (#token_expires_at)
    #            :none   — the credential does not expire (an API key)
    #   refresh  :server         — we renew it ourselves (#refresh!), and the sweep does
    #            :container_only — only the CLI inside the container can renew it
    #            :reauth_only    — nothing can renew it; the user must sign in again
    #            :none           — nothing to renew
    #   rotation :rotating — a refresh invalidates the grant it replaced (single-use
    #                        refresh token: every other holder of it is now stale)
    #            :static   — it does not
    #   nominal_ttl — the vendor's documented/measured token life, nil when unknown
    #   reauth_required_on_expiry — set only when `expiry: :token` meets a `refresh` that
    #            cannot renew: the acknowledgement that the expiry we surface is a
    #            re-login instruction, not something a sweep will fix
    # @return [Hash]
    def credential_lifecycle
      { expiry: :none, refresh: :none, rotation: :static, nominal_ttl: nil }.freeze
    end

    # Expiry (epoch ms) of the login the CLI cannot run without, or nil when this agent
    # has none that expires. Distinct from #token_expires_at, which reports the SOONEST
    # expiry across every stored block so the refresh sweep fires early: an agent that
    # layers add-on grants onto a base login (Claude's designOauth) would otherwise read
    # as unusable whenever an add-on lapses, and refuse launches that would have worked.
    # Default: the same value, which is correct for every single-block agent.
    # @param credentials [Hash] decrypted credential data
    # @return [Integer, nil]
    def base_token_expires_at(credentials)
      token_expires_at(credentials)
    end

    # Decode the `exp` claim (seconds since epoch) from a JWT payload WITHOUT
    # verifying the signature, returning epoch milliseconds — or nil when the
    # value is not a three-segment JWT or carries no `exp`. Adapters whose access
    # tokens are JWTs (Codex, Cursor) use this to implement #token_expires_at so
    # the proactive-refresh sweep can select them.
    # @param token [String, nil]
    # @return [Integer, nil]
    def jwt_exp_ms(token)
      exp = jwt_claims(token)["exp"]
      exp.present? ? exp.to_i * 1000 : nil
    end

    # The unverified payload of a JWT, or {} when the token is not one.
    def jwt_claims(token)
      return {} if token.blank?

      segments = token.to_s.split(".")
      return {} unless segments.size == 3

      claims = JSON.parse(Base64.urlsafe_decode64(base64_pad(segments[1])))
      claims.is_a?(Hash) ? claims : {}
    rescue StandardError
      {}
    end

    # Merge freshly-collected credentials (from a live session's container) onto the
    # stored blob before persisting. Default: replace wholesale, but keep the stored
    # blob when the incoming token is older (refresh-token rotation guard). Adapters
    # whose credentials hold multiple independently-rotating token blocks override this
    # to merge per block.
    # @param current [Hash] currently-stored credential data
    # @param incoming [Hash] credentials collected from the session container
    # @return [Hash] the blob to persist
    # == What a running container may write back ==
    #
    # The write-back endpoint and the cleanup collector both read the credential out
    # of the container, and the container is the thing that may be compromised. So it
    # may only ROTATE what the server already holds: a token the stored credential
    # already has, replaced by a fresher one for the same account whose expiry is
    # plausible for this runtime. Nothing else it sends is taken — not a new key, an
    # API key, a Bedrock block or a settings file — or a prompt-injected agent could
    # point every later session of its owner at an account or endpoint of its own.

    # The keys of the credential hash a session's container may replace. Default: none.
    def rotatable_credential_keys
      []
    end

    # The files the in-container watcher reports while a session runs; only those that
    # carry rotating tokens. Empty turns the write-back off for this runtime.
    def writeback_file_paths
      rotatable_credential_keys.empty? ? [] : auth_file_paths
    end

    # A write-back file whose content is bytes, not text; the watcher sends those base64.
    def binary_writeback_path?(_path)
      false
    end

    # The account a credential's tokens belong to, when the tokens say so (a JWT's
    # subject); nil when they cannot tell. A rotation must not change it.
    def credential_identity(_credentials)
      nil
    end

    # Rotations only. Returns `current` unchanged unless every rule holds.
    def merge_container_credentials(current, incoming)
      keys = rotatable_credential_keys & current.keys & incoming.keys
      return current if keys.empty?

      candidate = merge_refreshed_credentials(current, incoming.slice(*keys))
      rotated = current.merge(candidate.slice(*keys))
      return current if rotated == current
      return current unless same_credential_identity?(current, rotated) && plausible_expiry?(rotated)

      rotated
    end

    # Far enough past the runtime's nominal lifetime to be forged: a far-future expiry
    # was how a written-back token won every "which copy is freshest" comparison.
    MAX_PLAUSIBLE_TOKEN_LIFETIME = 90.days

    def plausible_expiry?(credentials)
      expires_ms = token_expires_at(credentials)
      return true if expires_ms.nil?

      ttl = credential_lifecycle[:nominal_ttl]
      horizon = ttl ? (ttl * 2) + 1.day : MAX_PLAUSIBLE_TOKEN_LIFETIME
      expires_ms.to_i <= ((Time.current + horizon).to_f * 1000)
    end

    def same_credential_identity?(current, rotated)
      held = credential_identity(current)
      held.nil? || credential_identity(rotated) == held
    end

    def merge_refreshed_credentials(current, incoming)
      new_exp = token_expires_at(incoming)
      old_exp = token_expires_at(current)
      return current if new_exp && old_exp && new_exp.to_i <= old_exp.to_i

      incoming
    end

    # Proactively refresh this credential's OAuth token(s) server-side, persisting
    # any rotated tokens back onto the AgentCredential. Every refresh — the sweep, a
    # launch, a request that found its token rejected — comes through here, under the
    # credential's refresh lease (RefreshLease): one refresher at a time, and the
    # provider call outside any transaction.
    #
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :not_needed | :error | :busy, detail: String | nil,
    #   permanent: Boolean } — `permanent` tells the refresh sweep whether the failure
    #   makes the credential unusable (flip it to `error`, forcing a re-login) or is a
    #   transient/partial one. :busy means another refresher holds the lease.
    # @param margin_ms [Integer, nil] how close to expiry a token must be to be worth
    #   refreshing. Only agents that store their own expiry (Claude, with a block per
    #   login) can honour it; single-block agents refresh whenever they are called.
    def refresh!(credential, margin_ms: nil)
      return NOT_REFRESHABLE unless server_refresh?

      outcome = credential.with_refresh_lease do
        stored = credential.encrypted_config_data
        result = perform_refresh!(credential, margin_ms: margin_ms)
        rotated_elsewhere?(credential, stored, result) ? ROTATED_ELSEWHERE : result.except(:persisted)
      end
      outcome == :busy ? REFRESH_BUSY : outcome
    end

    NOT_REFRESHABLE = { status: :not_needed, detail: nil, permanent: false }.freeze
    REFRESH_BUSY = { status: :busy, detail: "another refresh of this credential is in progress", permanent: false }.freeze
    ROTATED_ELSEWHERE = { status: :not_needed, detail: "the stored tokens changed while refreshing", permanent: false }.freeze

    def server_refresh?
      method(:perform_refresh!).owner != BaseAdapter
    end

    # A request found the stored access token rejected. Renewed through
    # AgentCredential#renew! like the sweep and a launch, so the outcome is recorded
    # and a failure reported: never rotating a refresh token a live container holds,
    # and never alongside another refresher — that one's result is taken instead.
    # Returns the credential's config after a refresh, or nil.
    def refresh_for_request!(credential)
      return nil if credential.rotating_refresh? && credential.held_by_live_session?

      result = credential.renew!(source: :unauthorized)
      credential.await_refresh if result[:status] == :busy
      result[:status].in?(%i[refreshed busy]) ? credential.reload.config_data : nil
    end

    # Adapter-specific refresh: call the provider, then persist through
    # #persist_refreshed! (or an equivalent read-merge-write under the row lock).
    # Report `persisted: true` in the result when anything was written. Default:
    # no-op (agents whose credentials don't carry a refreshable OAuth token).
    def perform_refresh!(_credential, margin_ms: nil)
      { status: :not_needed, detail: nil, permanent: false }
    end

    # A rejection only condemns the credential when it was of the tokens still
    # stored. If a container wrote rotated tokens back while the provider was being
    # asked, it rejected a grant that is no longer ours to judge by.
    def rotated_elsewhere?(credential, stored, result)
      return false unless result[:status] == :error && !result[:persisted]

      credential.class.where(id: credential.id).pick(:encrypted_config_data) != stored
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

    # =================================================================
    # Launch-time Credential Preflight
    # =================================================================

    # Verify the credentials already written to the container, run once
    # immediately after credential injection and before the CLI is launched in
    # tmux (AgentSessionStrategy#before_exec). Default: no-op — most agents have
    # no launch-time read-back to perform. An adapter that needs one (e.g. Codex,
    # whose CLI falls through to an interactive login on invalid auth) overrides
    # this to return a validity verdict.
    #
    # @param _runtime [ContainerRuntime::BaseRuntime] the strategy's runtime —
    #   passed in (rather than resolved via ContainerRuntime.build) so callers can
    #   inject a fake directly
    # @param _container [Object] runtime-specific container handle
    # @param _container_id [String]
    # @return [Hash, nil] { valid: Boolean, error_code: String } or nil when this
    #   agent has nothing to check
    def credential_preflight(_runtime, _container, _container_id)
      nil
    end

    def credential_file_metadata(runtime, container_id, path)
      stdout, stderr, status = runtime.exec(
        container_id, [ "/bin/sh", "-c", "stat -c '%s|%a|%U|%G' #{Shellwords.escape(path)} 2>&1" ], stdout: true, stderr: true
      )
      output = Array(stdout).join.strip
      size, mode, owner, group = output.split("|", 4) if status.to_i.zero?
      {
        path: path,
        container: container_id.to_s,
        exists: status.to_i.zero?,
        size: size&.to_i,
        mode: mode,
        owner: owner,
        group: group,
        stat_exit_status: status.to_i,
        stat_error: status.to_i.zero? ? nil : Array(stderr).join.strip.presence || output.presence
      }
    end

    # Facts about an account that can only be had by asking the vendor's own CLI,
    # collected while a container is still up and merged into the credential's
    # metadata. Default: nothing.
    #
    # This exists for what a server-side API call cannot answer reliably. Kiro is the
    # case: which service holds the model catalogue changed between its engine
    # versions, so the CLI knows the endpoint and we do not, and its `--list-models`
    # gives the catalogue the user's own subscription actually offers.
    #
    # Runs on the cleanup path of both the auth and the session strategy, so a freshly
    # connected runtime has the data before its first session, and it stays current
    # afterwards.
    #
    # @param _runtime [ContainerRuntime::BaseRuntime]
    # @param _container [Object] runtime-specific container handle
    # @param _credential [AgentCredential] the row the result is merged into — passed so
    #   an adapter can see what is already stored and leave it alone
    # @param _phase [Symbol] :auth when the credential has just been captured, :session
    #   at the end of an ordinary session. Facts that are only true of a fresh login
    #   belong to :auth — writing them on every session cleanup is how a "since last
    #   time" measurement gets reset to zero on the run it was meant to measure.
    # @return [Hash] merged into AgentCredential#metadata; empty to write nothing
    def collect_credential_metadata(_runtime, _container, _credential, _phase)
      {}
    end

    protected

    # Unparseable input is {} — including nil, which JSON.parse raises TypeError on
    # rather than the ParserError this used to catch. Callers reach here with whatever
    # a container, a vendor file or an absent database row handed over, and "there was
    # nothing to read" is an ordinary outcome for all three, not an exception.
    def parse_json(content)
      return {} if content.blank?

      JSON.parse(content)
    rescue JSON::ParserError, TypeError
      {}
    end

    # Right-pad a base64url segment to a multiple of 4 so Base64.urlsafe_decode64
    # (which is strict about padding) accepts a JWT payload segment.
    def base64_pad(str)
      str + ("=" * ((4 - (str.length % 4)) % 4))
    end
  end
end
