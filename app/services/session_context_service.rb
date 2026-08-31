# frozen_string_literal: true

require "shellwords"

# SessionContextService
# Injects session configuration into agent containers.
# Reads from TerminalSession#session_config:
#   - Config files (Story 9.2)
#   - Environment variables with secret resolution (Story 9.3)
#   - MCP server configurations per CLI format (Story 9.4)
#   - Skill files per CLI format (Story 9.6)
#   - Context file with MCP/tool descriptions and agent persona (Story 9.7)
class SessionContextService
  # Collects a structured log of everything injected into the container.
  # Written to /var/log/context.log for post-mortem debugging.
  class ContextLog
    # Values shorter than this are never redacted — they are common non-secret
    # tokens ("json", "true", "sse") whose masking would only obscure the log; real
    # credentials (bearer tokens, API keys, resolved config-item secrets) are longer.
    MIN_REDACT_LEN = 6

    def initialize(session)
      @session_id = session.id
      @agent_type = session.agent_type
      @mode = session.mode
      @started_at = Time.current
      @entries = []
      @secrets = []
    end

    def record(step, data)
      @entries << { step: step, data: data, at: Time.current.iso8601(3) }
    end

    def record_files(step, files_hash)
      return if files_hash.blank?

      @entries << { step: step, files: files_hash, at: Time.current.iso8601(3) }
    end

    # Register secret VALUES to scrub from the rendered log (oauth-unification §7).
    # We keep the structure (server names, header/env KEYS) but replace each secret
    # value with a stable fingerprint, so the log stays useful for audit/debugging
    # ("which header carried which secret") without exposing the bytes. Called with
    # the resolved header/env values + the injected OAuth bearer + the session key.
    def redact(*values)
      values.flatten.each do |value|
        s = value.to_s
        @secrets << s if s.length >= MIN_REDACT_LEN
      end
    end

    # Values known to be secrets — the `secret` config items attached to the
    # session — with no length floor. MIN_REDACT_LEN guards `redact` because it
    # receives every MCP header/env value, secret or not; here every value was
    # explicitly marked secret, and a short one is still a secret.
    def redact_known_secrets(*values)
      values.flatten.each do |value|
        s = value.to_s
        @secrets << s if s.present?
      end
    end

    def to_s
      lines = []
      lines << "=== Session Context Log ==="
      lines << "session_id: #{@session_id}"
      lines << "agent_type: #{@agent_type}"
      lines << "mode: #{@mode}"
      lines << "assembled_at: #{@started_at.iso8601(3)}"
      lines << ""

      @entries.each do |entry|
        if entry[:files]
          lines << "[#{entry[:at]}] #{entry[:step]}:"
          entry[:files].each do |path, content|
            lines << "--- #{path} ---"
            lines << content.to_s
            lines << "--- end #{path} ---"
            lines << ""
          end
        else
          lines << "[#{entry[:at]}] #{entry[:step]}: #{entry[:data].inspect}"
        end
      end

      lines << ""
      lines << "=== End Context Log ==="
      scrub_secrets(lines.join("\n"))
    end

    private

    # One implementation of the substitution, shared with the log-collection
    # sinks — a second copy would drift and produce two different fingerprints
    # for the same secret across artifacts of the same session.
    def scrub_secrets(text)
      Sessions::SecretRedactor.new(@secrets).call(text)
    end
  end

  class << self
    # == Story 9.8: Unified Session Context Assembly ==

    # Orchestrate all session context injection steps in correct order.
    # Single entry point for AgentSessionStrategy#before_exec.
    #
    # @param container_id [String] Container identifier
    # @param session [TerminalSession] Session record
    # @param credential [AgentCredential, nil] Optional credential to inject
    # @return [Boolean, nil] the credential write result — true/false when a
    #   credential was injected, nil when none was (mirrors #write_to_container,
    #   which itself only ever returns true or raises)
    def assemble_session_context(container_id, session, credential: nil)
      context_log = ContextLog.new(session)

      # Resolve MCP server names early — needed for pre-approving servers
      # in the credential config (e.g. Claude Code's enabledMcpjsonServers)
      resolved_servers = build_all_servers(session)
      # Normalized protocol keys (matches the .mcp.json keys the adapters write and
      # the mcp__<key> tool-permission namespace). Must stay in sync with
      # MCPServer.config_key_for used in each agent adapter's MCP config builder.
      mcp_server_names = resolved_servers.map { |s| MCPServer.config_key_for(s.name) }
      # Register every resolved secret (header/env values incl. the injected OAuth
      # bearer, plus the session mcp_key) so they are scrubbed from the collected
      # /var/log/context.log artifact (oauth-unification §7). The real values still
      # reach the container's MCP config files — only the log copy is redacted.
      context_log.redact(collect_context_secrets(resolved_servers, session))
      # Config items attached to this session: the context file lists their
      # NAMES, but a value could still reach the log through an MCP header that
      # references the same item, so register them here too.
      context_log.redact_known_secrets(Sessions::SecretRedactor.secret_values_for(session))
      context_log.record(:mcp_servers, mcp_server_names)
      Rails.logger.info("[SessionContext] Pre-resolved MCP server names: #{mcp_server_names.inspect}")

      # Step 1: Credentials (optional)
      credential_write_result = nil
      if credential.present?
        measure_step("credentials") do
          resolved_model = resolve_session_model(session, credential)
          workflow_config = { enabled_mcp_servers: mcp_server_names, model: resolved_model, mode: session.mode }.compact
          Rails.logger.info("[SessionContext] Writing credentials with workflow_config: #{workflow_config.inspect}")
          credential_write_result = credential.write_to_container(container_id, workflow_config)
          context_log.record(:credentials, agent_type: credential.agent_type, config_keys: credential.config_data.keys, workflow_config: workflow_config)
        end
      end

      # Step 2: Config files
      measure_step("config_files") { inject_config_files(container_id, session) }
      context_log.record(:config_files, session.config_files.keys)

      # Step 3: MCP config
      mcp_content = measure_step("mcp_config") { inject_mcp_config(container_id, session) }
      context_log.record_files(:mcp_config, mcp_content)

      # Step 4: Skills
      skill_content = measure_step("skills") { inject_skills(container_id, session) }
      context_log.record_files(:skills, skill_content)

      # Step 5: Assets
      measure_step("assets") { inject_assets(container_id, session) }
      context_log.record(:assets, session.input_asset_ids || [])

      # Step 6: Repositories (shallow clone from GitHub)
      measure_step("repositories") { inject_repositories(container_id, session) }
      context_log.record(:repositories, session.repositories.pluck(:full_name))

      # Step 7: BMAD Method (install after repos, before context file)
      if SessionConfigResolver.new(session).resolve_bmad_enabled
        measure_step("bmad_method") do
          BmadMethodInjector.new(container_id, session, runtime: runtime).inject!
        end
        context_log.record(:bmad_method, modules: session.bmad_modules)
      end

      # Step 8: Context file (after skills + BMAD)
      ctx_content = measure_step("context_file") { inject_context_file(container_id, session) }
      context_log.record_files(:context_file, ctx_content)

      # Step 9: Write context log to container for debugging
      measure_step("context_log") { write_context_log(container_id, context_log) }

      Rails.logger.info("[SessionContext] Assembly complete for session #{session.id}")
      credential_write_result
    end

    # == Story 9.2: Config File Injection ==

    # Inject config files from session_config into container.
    # Expands ~ to agent home directory, creates parent dirs, sets ownership.
    def inject_config_files(container_id, session)
      files = session.config_files
      return if files.blank?

      adapter = adapter_for(session)

      files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)
        write_file(container_id, expanded, content, adapter.container_uid)
        Rails.logger.info("[SessionContext] Injected config file: #{path} (#{content.bytesize} bytes)")
      end
    end

    # == Story 9.6: Skill Injection ==

    # Install skills into container via `npx skills add`.
    # Each skill is installed globally (`-g`) for the target agent runtime,
    # so skill files land in the agent's home dir (not /workspace).
    #
    # TELEMETRY IS OFF, DELIBERATELY. Every `skills add` otherwise POSTs an install
    # event to add-skill.vercel.sh carrying the source, the skill slugs, the agent,
    # and `skillFiles` — a map of skill name to the relative path it was installed
    # to (paths, not contents; see vercel-labs/skills src/telemetry.ts). Two reasons
    # to switch it off: it publishes what every session here installs and where, and
    # it makes this platform a contributor to the very leaderboard the catalog is
    # ranked by.
    #
    # `env VAR=1 cmd` rather than an exec option because neither container runtime
    # accepts an env hash in `exec` opts.
    def inject_skills(container_id, session)
      skills = resolve_skills(session)
      return {} if skills.empty?

      adapter = adapter_for(session)
      return {} if adapter.includes_skills_in_context?

      manual, registry = skills.partition(&:manual?)
      installed = {}

      # `skills_agent_name` is only resolved when there is something for the CLI to
      # do — a runtime that never implemented it can still receive manual skills.
      registry.each { |skill| installed[skill_key(skill)] = install_registry_skill(container_id, adapter, skill) }
      manual.each { |skill| installed[skill_key(skill)] = write_manual_skill(container_id, adapter, skill) }

      installed
    end

    def install_registry_skill(container_id, adapter, skill)
      agent_name = adapter.skills_agent_name
      cmd = [
        "env", "DISABLE_TELEMETRY=1",
        "npx", "-y", "skills", "add", skill.source,
        # The slug as upstream published it, taken from `package` ("source@slug")
        # rather than from `name`, which the model downcases. `--skill` matches
        # upstream's own directory name, so a normalised value would simply miss.
        "--skill", registry_slug(skill),
        "-a", agent_name,
        "-g", "--copy", "-y"
      ]

      _stdout, stderr, status = runtime.exec(container_id, cmd, timeout: 30)

      if status.zero?
        Rails.logger.info("[SessionContext] Installed skill via npx: #{skill.package} -> #{agent_name}")
        "ok"
      else
        Rails.logger.warn("[SessionContext] Failed to install skill #{skill.package}: #{stderr}")
        "error: #{stderr.to_s.truncate(200)}"
      end
    end

    # A hand-written skill is written straight into the directory the CLI would have
    # used, and never handed to the CLI itself — an install event naming a private
    # skill has no business leaving this deployment. The path matches the CLI's own
    # `globalSkillsDir` per agent (vercel-labs/skills src/agents.ts), so a manual
    # skill lands exactly where an installed one does.
    def write_manual_skill(container_id, adapter, skill)
      dir = adapter.skills_install_path
      if dir.blank?
        Rails.logger.warn("[SessionContext] #{adapter.class} has no skills directory; skipping #{skill.name}")
        return "error: runtime has no skills directory"
      end

      # The Agent Skills spec requires the directory name to equal the skill's
      # `name`, which is why the manual form validates that name so strictly.
      #
      # Written through the service's own helper so it lands with the agent's uid:
      # writing as root would create ~/.claude and ~/.claude/skills owned by root
      # before the agent (uid 1001) ever touches them, and every later write by the
      # agent into that tree would fail with EACCES.
      path = "#{dir}/#{skill.name}/SKILL.md"
      if write_file(container_id, path, skill.content.to_s, adapter.container_uid)
        Rails.logger.info("[SessionContext] Wrote manual skill: #{path}")
        "ok"
      else
        Rails.logger.warn("[SessionContext] Failed to write manual skill: #{path}")
        "error: write failed"
      end
    end

    # Manual skills have no registry package, so they report under their name.
    def skill_key(skill)
      skill.package.presence || skill.name
    end

    # "owner/repo@slug" → "slug", falling back to the stored name.
    def registry_slug(skill)
      skill.package.to_s.split("@").last.presence || skill.name
    end

    # == Story 9.7 → 25.7: Context File Injection (via Constructor) ==

    # Delegates context generation to SessionContextConstructor.
    # Produces XML-tagged markdown with priority-sorted sections.
    # Stores JSON metadata on session for traceability.
    def inject_context_file(container_id, session)
      session.reload
      result = SessionContextConstructor.build_result(session)
      content = result.render
      return {} if content.blank?

      adapter = adapter_for(session)
      path = adapter.context_file_path
      return {} if path.blank?

      expanded = expand_path(path, adapter.home_dir)
      write_file(container_id, expanded, content, adapter.container_uid)

      merged_metadata = (session.context_metadata || {}).merge(result.to_json_hash)
      session.update_column(:context_metadata, merged_metadata)

      Rails.logger.info("[SessionContext] Injected context file: #{path} (#{content.bytesize} bytes, #{result.applied_builders.size} builders)")
      { path => content }
    end

    # == Story 9.4: MCP Config Injection ==

    # Generate and inject MCP server config files into container.
    # Always includes internal Aixle MCP + external servers from session_config.
    # Delegates format generation to adapter, handles merge strategy.
    def inject_mcp_config(container_id, session)
      all_servers = build_all_servers(session)
      return {} if all_servers.empty?

      adapter = adapter_for(session)
      config_files = adapter.mcp_config(all_servers)
      return {} if config_files.blank?

      config_files.each do |path, content|
        expanded = expand_path(path, adapter.home_dir)
        write_mcp_file(container_id, expanded, content, adapter.mcp_merge_strategy, adapter.container_uid)
        Rails.logger.info("[SessionContext] Injected MCP config: #{path} (#{adapter.mcp_merge_strategy})")
      end

      config_files
    end

    # Generate MCP config content (without injecting).
    # @return [Hash] { path => content } mapping
    def generate_mcp_config(session)
      all_servers = build_all_servers(session)
      return {} if all_servers.empty?

      adapter = adapter_for(session)
      adapter.mcp_config(all_servers)
    end

    # Resolve model for a session: step preferred > session requested > credential default > nil
    def resolve_session_model(session, credential)
      # For workflow steps, check the step's preferred model first
      if session.session_type == "workflow_step" && session.step_run&.step&.preferred_model.present?
        return session.step_run.step.preferred_model
      end

      # Session-level requested model
      return session.requested_model if session.requested_model.present?

      # User's default model from credential metadata (retired ids mapped forward)
      credential&.default_model
    end

    private

    CONTEXT_LOG_PATH = "/var/log/context.log"

    def write_context_log(container_id, context_log)
      runtime.write_file(container_id, CONTEXT_LOG_PATH, context_log.to_s)
    rescue => e
      Rails.logger.warn("[SessionContext] Failed to write context log: #{e.message}")
    end

    # == Timing ==

    def measure_step(name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      Rails.logger.info("[SessionContext] Step '#{name}' completed in #{elapsed}ms")
      result
    end

    # == Shared Helpers ==

    def adapter_for(session)
      AgentCredentialsService.for(session.agent_type).adapter
    end

    def expand_path(path, home_dir)
      path.sub(/\A~/, home_dir)
    end

    def resolve_effective_config_items(session)
      return {} unless session.project.present?

      ConfigItem.effective_for_project(session.project)
    end

    # Resolve embedded config_item:NAME references (for headers like "Bearer config_item:KEY")
    def resolve_embedded_references(value, effective_items)
      return value unless value.is_a?(String) && value.include?("config_item:")

      value.gsub(/config_item:(\w+)/) do
        item_name = ::Regexp.last_match(1)
        resolved = effective_items[item_name]
        unless resolved
          Rails.logger.warn("[SessionContext] ConfigItem '#{item_name}' not found in header")
          next "config_item:#{item_name}"
        end
        resolved
      end
    end

    # Legacy context builders removed in Story 25.7.
    # Context generation now handled by SessionContextConstructor and ContextBuilders::*.

    # == Skill Resolution ==

    def resolve_skills(session)
      ids = session.skill_ids
      return [] if ids.blank?

      skills = Skill.where(id: ids).to_a
      found_ids = skills.map(&:id)
      missing = ids - found_ids

      missing.each { |id| Rails.logger.warn("[SessionContext] Skill #{id} not found, skipping") }
      skills
    end

    # == Asset Injection ==

    def inject_assets(container_id, session)
      ids = session.input_asset_ids
      return if ids.blank?

      assets = Asset.where(id: ids).includes(:versions).to_a
      missing = ids - assets.map(&:id)
      missing.each { |id| Rails.logger.warn("[SessionContext] Asset #{id} not found, skipping") }

      adapter = adapter_for(session)
      uid = adapter.container_uid

      assets.each do |asset|
        version = asset.latest_version
        unless version&.file
          Rails.logger.warn("[SessionContext] Asset '#{asset.name}' has no file, skipping")
          next
        end

        folder = asset.folder.present? ? "#{asset.folder}/" : ""
        target_path = "/workspace/assets/#{folder}#{asset.name}"
        url = container_accessible_url(version.file.url)

        download_file_to_container(container_id, url, target_path, uid)
      end
    end

    # == Repository Injection ==

    def inject_repositories(container_id, session)
      ids = session.repository_ids
      return if ids.blank?

      # Ordered: an unordered `where` lets Postgres hand back rows in whatever order
      # it likes, which reshuffles the `repositories:` list sent to GitHub for the
      # group token and the order repositories clone in — a difference that shows up
      # as a test failing only on some runs.
      repos = Repository.where(id: ids).order(:id).includes(:integration).to_a
      return if repos.empty?

      adapter = adapter_for(session)
      uid = adapter.container_uid

      repos.group_by(&:integration_id).each do |integration_id, group_repos|
        # Public repositories carry no integration: they are cloned anonymously,
        # so there is no token to mint and nothing to share across the group.
        if integration_id.nil?
          group_repos.each { |repo| clone_repository(container_id, repo, nil, nil, uid, session) }
          next
        end

        integration = group_repos.first.integration
        unless integration&.active?
          group_repos.each { |r| record_failed_repo(session, r, "Integration not active") }
          next
        end

        token = begin
          generate_clone_token(integration, group_repos)
        rescue => e
          Rails.logger.warn("[SessionContext] Group token failed for integration #{integration.id}: #{e.message}")
          nil
        end

        if token
          group_repos.each { |repo| clone_repository(container_id, repo, integration, token, uid, session) }
        else
          clone_with_per_repo_tokens(container_id, group_repos, integration, uid, session)
        end
      end
    end

    # One repository the installation cannot reach (attached before the App lost
    # access to it, say) fails the WHOLE group's token — GitHub rejects the
    # `repositories:` list wholesale with a 422. Falling back to a token per
    # repository keeps the failure with the repository that caused it.
    def clone_with_per_repo_tokens(container_id, group_repos, integration, uid, session)
      group_repos.each do |repo|
        token = begin
          generate_clone_token(integration, [ repo ])
        rescue => e
          Rails.logger.error("[SessionContext] Failed to generate token for #{repo.full_name}: #{e.message}")
          record_failed_repo(session, repo, "Token generation failed: #{e.message}")
          next
        end

        clone_repository(container_id, repo, integration, token, uid, session)
      end
    end

    def generate_clone_token(integration, group_repos)
      case integration.provider.to_s
      when "github"
        repo_names = group_repos.map(&:repo_name)
        Github::TokenService.new(integration).generate_installation_token(repositories: repo_names)
      when "gitlab"
        integration.credentials_data["personal_access_token"]
      else
        raise "Unsupported provider: #{integration.provider}"
      end
    end

    def clone_repository(container_id, repo, integration, token, uid, session)
      target_path = "/workspace/repo/#{repo.repo_name}"
      2.times do |index|
        result = exec_clone_command(container_id, repo, integration, token, uid, target_path)
        exit_code = result[2]

        if exit_code.to_i.zero?
          repo.update_column(:last_fetched_at, Time.current)
          Rails.logger.info("[SessionContext] Cloned repository: #{repo.full_name} → #{target_path}")
          return
        end

        stderr = Array(result[1]).join
        raise "git clone exited with #{exit_code}: #{stderr}" if index == 1

        sleep 2
      end
    rescue => e
      Rails.logger.error("[SessionContext] Failed to clone #{repo.full_name}: #{e.message}")
      record_failed_repo(session, repo, e.message)
    end

    def exec_clone_command(container_id, repo, integration, token, uid, target_path)
      clone_url = build_clone_url(repo, integration, token)
      branch = Shellwords.escape(repo.source_branch)
      cmd = [ "sh", "-c", "git clone --depth=1 --branch=#{branch} #{clone_url} #{target_path} && chown -R #{uid}:#{uid} #{target_path}" ]
      runtime.exec(container_id, cmd)
    end

    # Public repositories clone with no credentials at all. Their clone_url is
    # validated by Repository to be the anonymous https url of full_name on an
    # allowlisted host, which is what makes it safe to interpolate here.
    def build_clone_url(repo, integration, token)
      return Shellwords.escape(repo.clone_url) if integration.nil?

      case integration.provider.to_s
      when "github"
        "https://x-access-token:#{token}@github.com/#{repo.full_name}.git"
      when "gitlab"
        "https://oauth2:#{token}@gitlab.com/#{repo.full_name}.git"
      else
        Shellwords.escape(repo.clone_url)
      end
    end

    def record_failed_repo(session, repo, error)
      meta = session.metadata || {}
      meta["failed_repos"] ||= []
      meta["failed_repos"] << { "id" => repo.id, "full_name" => repo.full_name, "error" => error.to_s.truncate(500) }
      session.update_column(:metadata, meta)
    end

    # == Container File Operations ==

    # A runtime that returns false has swallowed the error (DockerRuntime rescues
    # StandardError). Without this log a failed write is completely silent and only
    # surfaces later as the agent behaving as if the file were never provisioned.
    def write_file(container_id, path, content, uid = 1001)
      return if path.blank?

      result = runtime.write_file(container_id, path, content, uid: uid.to_i, gid: uid.to_i)
      Rails.logger.error("[SessionContext] FAILED to write container file: #{path}") if result == false
      result
    end

    def download_file_to_container(container_id, url, target_path, uid)
      safe_dir = Shellwords.escape(File.dirname(target_path))
      safe_path = Shellwords.escape(target_path)
      safe_url = Shellwords.escape(url)

      cmd = [ "sh", "-c", "mkdir -p #{safe_dir} && curl -fsSL -o #{safe_path} #{safe_url} && chown #{uid}:#{uid} #{safe_path}" ]
      result = runtime.exec(container_id, cmd)
      exit_code = result[2]

      if exit_code.to_i.zero?
        Rails.logger.info("[SessionContext] Downloaded asset: #{target_path}")
      else
        stderr = Array(result[1]).join
        Rails.logger.error("[SessionContext] Failed to download asset to #{target_path}: exit=#{exit_code} #{stderr}")
      end
    end

    def container_accessible_url(url)
      host = Settings.container_asset_host
      return url if host.blank?

      override = URI.parse(host.start_with?("http") ? host : "http://#{host}")
      uri = URI.parse(url)
      uri.scheme = override.scheme
      uri.host = override.host
      uri.port = override.port
      uri.to_s
    end

    def read_file(container_id, path)
      return nil if path.blank?

      runtime.read_file(container_id, path)
    rescue StandardError => e
      Rails.logger.debug("[SessionContext] read_file(#{path}) failed: #{e.message}")
      nil
    end

    # == MCP Server Resolution ==

    # Combine internal Aixle MCP + resolved custom external servers.
    def build_all_servers(session)
      effective_items = resolve_effective_config_items(session)
      external = resolve_mcp_servers(session)
                   .map { |s| resolve_server_secrets(s, effective_items, session) }

      [ build_internal_mcp(session) ] + external
    end

    # Secret VALUES to scrub from context.log (oauth-unification §7): every resolved
    # MCP header/env value (includes the injected OAuth bearer and the internal
    # aixle-tools X-Session-Key) plus the session mcp_key. Values only — KEYS and
    # server names stay so the log remains auditable.
    def collect_context_secrets(servers, session)
      values = servers.flat_map do |server|
        headers = server.respond_to?(:headers) ? (server.headers || {}).values : []
        env     = server.respond_to?(:env) ? (server.env || {}).values : []
        headers + env
      end
      (values + [ session.mcp_key ]).compact.map(&:to_s).reject(&:blank?)
    end

    # Build internal Aixle MCP server entry (always included in session containers)
    def build_internal_mcp(session)
      OpenStruct.new(
        name: "aixle-tools",
        url: Settings.mcp.server_url,
        transport: "streamable-http",
        headers: { "X-Session-Key" => session.mcp_key }
      )
    end


    def resolve_mcp_servers(session)
      ids = session.mcp_server_ids
      return [] if ids.blank?

      servers = MCPServer.where(id: ids, enabled: true).to_a
      found_ids = servers.map(&:id)
      missing = ids - found_ids

      missing.each { |id| Rails.logger.warn("[SessionContext] MCPServer #{id} not found or disabled, skipping") }
      servers
    end

    def resolve_server_secrets(server, effective_items, session = nil)
      resolved_headers = (server.headers || {}).transform_values do |value|
        resolve_embedded_references(value, effective_items)
      end

      resolved_env = (server.env || {}).transform_values do |value|
        resolve_embedded_references(value, effective_items)
      end

      # OAuth injection (oauth-unification §4.4). No-op unless the server is an
      # OAuth server; a resolved token becomes an `Authorization: Bearer` header.
      inject_oauth_token!(server, resolved_headers, session)

      attrs = {
        name: server.name,
        url: server.url,
        transport: server.transport.to_s,
        headers: resolved_headers,
        env: resolved_env
      }

      # The adapters see this OpenStruct, never the record, so the two ways a launch
      # line can be stored have to be reconciled here — see MCPServer#launch_args.
      if server.transport_stdio?
        attrs[:command] = server.command_executable
        attrs[:args] = server.launch_args
      end

      OpenStruct.new(attrs)
    end

    # Scope-aware OAuth injection (oauth-unification §4.4). Only OAuth servers are
    # considered (none/static ⇒ no-op); an explicit Authorization header is never
    # overwritten. On success injects a Bearer header resolved for the right
    # identity (per_user ⇒ session.user; shared ⇒ the server's scope owner).
    #
    # ReauthRequired is deliberately NOT rescued here: it must propagate to the
    # session-start preflight (§4.6) so we never silently launch a session with a
    # missing or dead per_user credential — the preflight surfaces a "Connect" CTA.
    # `respond_to?(:auth_type)` guards the internal aixle-tools OpenStruct entry.
    def inject_oauth_token!(server, headers, session)
      return if session.nil?
      return unless server.respond_to?(:auth_type) && server.auth_type_oauth?
      return if headers.key?("Authorization") || headers.key?("authorization")

      token = Oauth::TokenService.access_token_for(server: server, user: session.user)
      headers["Authorization"] = "Bearer #{token}" if token.present?
    end

    # Write MCP config file respecting merge strategy
    def write_mcp_file(container_id, path, content, strategy, uid)
      case strategy
      when :merge_json
        existing_content = read_file(container_id, path)
        existing = existing_content.present? ? JSON.parse(existing_content) : {}
        new_data = JSON.parse(content)
        merged = existing.merge(new_data)
        write_file(container_id, path, merged.to_json, uid)
      when :append_toml
        append_toml(container_id, path, content, uid)
      else # :fresh
        write_file(container_id, path, content, uid)
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("[SessionContext] Failed to parse existing file #{path}: #{e.message}, writing fresh")
      write_file(container_id, path, content, uid)
    end

    # Appending is a read-modify-write, and `read_file` answers nil both for "the
    # file is not there" and for "the read failed" — so the naive version wrote the
    # MCP block on its own whenever a container hiccup swallowed the read, silently
    # discarding everything the credential step had put in the same file. For Codex
    # that file is config.toml, which holds the trusted-project entry: the result
    # still parses, so the CLI starts and asks "Do you trust the contents of this
    # directory?", and a non_interactive session has nobody to answer (task #605).
    #
    # An existing file we could not read is therefore left alone. Losing MCP servers
    # surfaces as an agent reporting a missing tool; losing the trust entry surfaces
    # as a workflow step that never speaks again.
    def append_toml(container_id, path, content, uid)
      existing = read_file(container_id, path)

      if existing.nil?
        presence = file_presence(container_id, path)

        # Only positively established absence may be overwritten. A probe that
        # errored answers :unknown, and the transient failure that swallowed the
        # read is exactly the one likeliest to swallow the probe too — treating
        # that as "absent" would recreate the loss this guard exists to prevent.
        if presence != :absent
          Rails.logger.error(
            "[SessionContext] Skipped MCP append to #{path}: the file could not be read and its " \
            "existence could not be ruled out (probe: #{presence}); overwriting it would drop the " \
            "config already written there"
          )
          return false
        end
      end

      write_file(container_id, path, "#{existing}\n\n#{content}", uid)
    end

    # Tri-state on purpose — see append_toml. A boolean would have to fold "the
    # probe could not answer" into one of the two answers, and both foldings are
    # wrong: `false` overwrites a file that may exist, `true` blocks the very
    # first write on a container whose exec is merely slow to warm up.
    #
    # Absence is only established by `test -f` exiting 1 with a silent stderr,
    # which is what the shell itself reports for a path that is not there. Any
    # other exit code is the transport failing, not the file missing.
    #
    # @return [Symbol] :present, :absent or :unknown
    def file_presence(container_id, path)
      _stdout, stderr, exit_code = runtime.exec(
        container_id, [ "/bin/sh", "-c", "test -f #{Shellwords.escape(path)}" ], stdout: true, stderr: true
      )
      return :present if exit_code.to_i.zero?
      return :absent if exit_code.to_i == 1 && Array(stderr).join.strip.empty?

      :unknown
    rescue StandardError => e
      Rails.logger.warn("[SessionContext] file_presence(#{path}) probe failed: #{e.message}")
      :unknown
    end

    def runtime
      Thread.current[:session_context_runtime] ||= ContainerRuntime.build
    end
  end
end
