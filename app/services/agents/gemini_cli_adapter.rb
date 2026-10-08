# frozen_string_literal: true

module Agents
  # Google Gemini CLI adapter for credential handling
  #
  # Config structure (discovered from container):
  #   ~/.gemini/oauth_creds.json - OAuth tokens (access_token, refresh_token, etc.)
  #   ~/.gemini/gemini-credentials.json - Encrypted API key (when using API key auth)
  #   ~/.gemini/settings.json - Auth settings (selectedType: oauth-personal | gemini-api-key)
  #   ~/.gemini/google_accounts.json - Account info
  class GeminiCliAdapter < BaseAdapter
    LOG_EVENT_NAME = "gemini_cli.api_response"

    API_KEY_CREDS_PATH = "gemini-credentials.json"

    def self.default_config_paths
      [ "~/.gemini/settings.json", "GEMINI.md" ]
    end

    def config_path
      "#{home_dir}/.gemini/#{API_KEY_CREDS_PATH}"
    end

    def home_dir
      "/home/gemini"
    end

    # Watch the actual API-key credential file. gemini-credentials.json only appears
    # once the user has entered the key (the CLI encrypts and writes it). We must NOT
    # watch settings.json: its `security` block is written at auth-METHOD selection,
    # before the key is entered, so the watcher would report success prematurely and
    # the auth container would close before the user finishes.
    # An API key: it does not expire, nothing rotates, and there is nothing to refresh.
    # The OAuth login path is deliberately not offered (see #config_files).
    def credential_lifecycle
      { expiry: :none, refresh: :none, rotation: :static, nominal_ttl: nil }.freeze
    end

    def auth_watch_path
      "#{home_dir}/.gemini/#{API_KEY_CREDS_PATH}"
    end

    # Auth files to extract at cleanup
    def auth_file_paths
      [
        "#{home_dir}/.gemini/#{API_KEY_CREDS_PATH}",
        "#{home_dir}/.gemini/settings.json"
      ]
    end

    # The credential file is an encrypted (non-JSON) blob, so completion = the file
    # exists with content. The watcher treats __present__ as "file present & non-empty".
    def auth_required_keys
      %w[__present__]
    end

    # Server-side completion check (gates credential persistence). The encrypted
    # gemini-credentials.json is a non-blank, non-JSON blob → complete. settings.json
    # is valid JSON but only marks the chosen auth method, so it must NOT count.
    def auth_complete?(config_content)
      parsed = parse_json(config_content)
      return false if parsed.is_a?(Hash) && parsed.any?

      config_content.to_s.strip.present?
    end

    # Not used directly — API key is extracted via decrypt in save_credentials
    def extract_credentials(_config_content)
      {}
    end

    def generate_config(credentials, _workflow_config = {})
      credentials
    end

    # API key auth: GEMINI_API_KEY env var + settings.json. Also pre-trusts the
    # workspace so the agent session doesn't stop on the folder-trust prompt.
    def config_files(_credentials, workflow_config = {})
      workspace = workflow_config[:workspace] || "/workspace"
      {
        "#{home_dir}/.gemini/settings.json" => generate_settings(
          model: workflow_config[:model], auth_type: "gemini-api-key"
        ).to_json
      }.merge(trusted_folders_files(workspace))
    end

    # Written before auth starts (AgentAuthStrategy#before_exec) so the auth
    # terminal is locked to the supported API-key flow and trusts /workspace.
    # OAuth tokens are not valid GEMINI_API_KEY values; allowing the auth picker
    # here can create a credential that looks connected but fails provider calls.
    def auth_setup_files
      {
        "#{home_dir}/.gemini/settings.json" => generate_settings(auth_type: "gemini-api-key").to_json
      }.merge(trusted_folders_files)
    end

    # Gemini CLI persists folder trust to ~/.gemini/trustedFolders.json (this exact
    # shape is what it writes when the user picks "Trust folder"). Writing it upfront
    # pre-trusts the workspace. `security.folderTrust.enabled: false` in settings.json
    # does not reliably suppress the prompt in current CLI versions, so this is the
    # source of truth.
    def trusted_folders_files(workspace = "/workspace")
      { "#{home_dir}/.gemini/trustedFolders.json" => { workspace => "TRUST_FOLDER" }.to_json }
    end

    # Pass API key as env var — Gemini CLI picks it up automatically
    def default_env_vars(session)
      env = { "OTEL_RESOURCE_ATTRIBUTES" => UsageStatistics::SessionKey.resource_attributes(session) }

      # Inject the API key from the credential of THIS session's company: keys are per
      # company so the vendor bill lands on the company that ran the session.
      credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: "gemini_cli")
      env["GEMINI_API_KEY"] = credential.config_data["api_key"] if credential&.config_data&.dig("api_key").present?

      env.compact
    end

    # Decrypt gemini-credentials.json from container.
    # Gemini CLI encrypts with AES-256-GCM, key derived via scrypt from hostname+username.
    def decrypt_credentials_file(encrypted_data, hostname, username = "root")
      parts = encrypted_data.strip.split(":")
      raise "Invalid format: expected iv:authTag:ciphertext" unless parts.length == 3

      iv = [ parts[0] ].pack("H*")
      auth_tag = [ parts[1] ].pack("H*")
      ciphertext = [ parts[2] ].pack("H*")

      salt = "#{hostname}-#{username}-gemini-cli"
      key = OpenSSL::KDF.scrypt("gemini-cli-oauth", salt: salt, N: 16384, r: 8, p: 1, length: 32)

      decipher = OpenSSL::Cipher.new("aes-256-gcm")
      decipher.decrypt
      decipher.key = key
      decipher.iv_len = iv.bytesize
      decipher.iv = iv
      decipher.auth_tag = auth_tag
      decrypted = decipher.update(ciphertext) + decipher.final

      # Structure: { "gemini-cli-api-key": { "default-api-key": "{\"token\":{\"accessToken\":\"...\"}}" } }
      data = JSON.parse(decrypted)
      api_key_json = data.dig("gemini-cli-api-key", "default-api-key")
      return nil unless api_key_json

      api_key_data = JSON.parse(api_key_json)
      api_key_data.dig("token", "accessToken")
    end

    def session_command(mode:, model: nil)
      model ? "gemini --model #{Shellwords.shellescape(model)} --yolo" : "gemini --yolo"
    end

    # Context file: ~/.gemini/GEMINI.md (auto-read by Gemini CLI at startup)
    def context_file_path
      "#{home_dir}/.gemini/GEMINI.md"
    end

    def skills_agent_name
      "gemini-cli"
    end

    # Where `skills add -g -a gemini-cli` puts a skill: the CLI installs into the
    # agent's own config directory, the same one holding settings.json.
    def skills_install_path
      "#{home_dir}/.gemini/skills"
    end

    # MCP config: merged into ~/.gemini/settings.json
    def mcp_config(servers)
      mcp_servers = {}
      servers.each do |s|
        entry = { "trust" => true }
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args) && s.args.present?
          entry["env"] = mcp_stdio_env(s)
        else
          entry["httpUrl"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[MCPServer.config_key_for(s.name)] = entry
      end
      { "#{home_dir}/.gemini/settings.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    def mcp_merge_strategy
      :merge_json
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # =================================================================

    # Fetch available models from Google Generative Language API.
    GEMINI_MODELS_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    FALLBACK_GEMINI_MODELS = [
      { model_id: "gemini-2.5-pro", display_name: "Gemini 2.5 Pro", description: "Most capable Gemini model" },
      { model_id: "gemini-2.5-flash", display_name: "Gemini 2.5 Flash", description: "Fast multimodal model, up to 1M tokens" },
      { model_id: "gemini-2.5-flash-lite", display_name: "Gemini 2.5 Flash-Lite", description: "Lightweight and fast" },
      { model_id: "gemini-2.0-flash", display_name: "Gemini 2.0 Flash", description: "Previous generation Flash model" },
      { model_id: "gemini-3.1-pro-preview", display_name: "Gemini 3.1 Pro Preview", description: "Latest preview model" }
    ].freeze

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(credentials, credential: nil)
      api_key = credentials["api_key"]
      access_token = credentials["access_token"]

      uri = URI(GEMINI_MODELS_URL)
      req = Net::HTTP::Get.new(uri)

      if api_key.present?
        uri.query = URI.encode_www_form(key: api_key, pageSize: 100)
        req = Net::HTTP::Get.new(uri)
      elsif access_token.present?
        uri.query = URI.encode_www_form(pageSize: 100)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{access_token}"
      else
        return { models: FALLBACK_GEMINI_MODELS, source: :fallback }
      end

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      unless response.is_a?(Net::HTTPSuccess)
        return { models: FALLBACK_GEMINI_MODELS, source: :fallback }
      end

      data = JSON.parse(response.body)
      models = (data["models"] || []).filter_map do |m|
        methods = m["supportedGenerationMethods"] || []
        next unless methods.include?("generateContent")

        model_id = m["name"].to_s.sub("models/", "")
        display_name = m["displayName"] || model_id

        next unless methods.include?("createCachedContent")

        { model_id: model_id, display_name: display_name, description: m["description"].to_s.truncate(120) }
      end

      if models.present?
        { models: models, source: :api }
      else
        { models: FALLBACK_GEMINI_MODELS, source: :fallback }
      end
    rescue StandardError => e
      Rails.logger.warn("[GeminiCliAdapter] fetch_available_models failed: #{e.message}")
      { models: FALLBACK_GEMINI_MODELS, source: :fallback }
    end


    # Parse OTLP payload and persist usage statistics for a terminal session.
    def ingest_usage(payload, terminal_session)
      new_events = extract_events_from_otlp(payload, terminal_session.route_token)

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: new_events)
    end

    private

    def generate_settings(model: nil, auth_type: "gemini-api-key")
      settings = {
        "security" => {
          "auth" => { "selectedType" => auth_type },
          # Don't ask for folder trust in containers
          "folderTrust" => {
            "enabled" => false
          }
        },
        # General settings
        "general" => {
          "vimMode" => false,
          "enableAutoUpdate" => false,     # Disable auto-update in containers
          "enableAutoUpdateNotification" => false
        },
        # UI settings for headless/container environment
        "ui" => {
          "hideBanner" => true,
          "hideTips" => true,
          "hideWindowTitle" => true,
          "dynamicWindowTitle" => false,
          "showHomeDirectoryWarning" => false
        },
        # Privacy
        "privacy" => {
          "usageStatisticsEnabled" => true  # Allow telemetry in containers
        },
        # Telemetry (OpenTelemetry)
        "telemetry" => {
          "enabled" => true,
          "target" => "local",
          "otlpEndpoint" => Settings.otel.endpoint.to_s,
          "otlpProtocol" => "http",
          "logPrompts" => false
        },
        # Tools - auto approve all operations (container is the sandbox)
        "tools" => {
          "sandbox" => false,                # Container is already sandboxed
          "useRipgrep" => true
        },
        # Experimental features
        "experimental" => {
          "useOSC52Paste" => true,           # Better paste in web terminal
          "enableAgents" => true             # Enable subagents
        }
      }
      settings["model"] = { "name" => model } if model.present?
      settings
    end

    # Usage is read from the `gemini_cli.api_response` log record, one per model response.
    # The CLI's `gemini_cli.token.usage` metric is CUMULATIVE — every export repeats the
    # running total — and it arrives in a separate request from the logs, so adding it up,
    # alongside the logs or not, counted a session's tokens several times over.
    def extract_events_from_otlp(payload, terminal_session_token)
      return [] if terminal_session_token.blank?

      extract_events_from_otlp_logs(payload, terminal_session_token)
    end

    def extract_events_from_otlp_logs(payload, terminal_session_token)
      events = []

      resource_logs = payload["resourceLogs"] || []
      resource_logs.each do |resource_log|
        resource_attrs = resource_log.dig("resource", "attributes") || []
        scope_logs = resource_log["scopeLogs"] || []

        scope_logs.each do |scope_log|
          log_records = scope_log["logRecords"] || []
          log_records.each do |log_record|
            attrs = log_record["attributes"] || []
            token_value = extract_terminal_session_token(attrs, resource_attrs)
            next if token_value != terminal_session_token

            event_name = attribute_string(attrs, "event.name")
            next unless event_name == LOG_EVENT_NAME

            input_tokens = attribute_number(attrs, "input_token_count").to_i
            output_tokens = attribute_number(attrs, "output_token_count").to_i
            cache_read_tokens = attribute_number(attrs, "cached_content_token_count").to_i
            # Gemini logs can include internal "thoughts/tool" buckets; treat as output-like generated tokens.
            output_tokens += attribute_number(attrs, "thoughts_token_count").to_i
            output_tokens += attribute_number(attrs, "tool_token_count").to_i
            total_cents = log_cost_cents(attrs)

            next if input_tokens.zero? && output_tokens.zero? && cache_read_tokens.zero? && total_cents.zero?

            events << build_usage_event(
              model: extract_model(attrs),
              timestamp_ns: log_record["timeUnixNano"],
              input_tokens: input_tokens,
              output_tokens: output_tokens,
              cache_read_tokens: cache_read_tokens,
              cache_write_tokens: 0,
              total_cents: total_cents
            )
          end
        end
      end

      events
    end

    def build_usage_event(model:, timestamp_ns:, input_tokens:, output_tokens:, cache_read_tokens:, cache_write_tokens:, total_cents:)
      {
        "model" => model,
        "timestamp" => timestamp_ns ? (timestamp_ns.to_i / 1_000_000).to_s : nil,
        "tokenUsage" => {
          "inputTokens" => input_tokens,
          "outputTokens" => output_tokens,
          "cacheReadTokens" => cache_read_tokens,
          "cacheWriteTokens" => cache_write_tokens,
          "totalCents" => total_cents.to_f
        },
        "source" => "otlp"
      }
    end

    def extract_model(attrs)
      attribute_string(attrs, "model") || attribute_string(attrs, "model_id")
    end

    def log_cost_cents(attrs)
      cents = attribute_number(attrs, "cost_cents")
      return cents.to_f if cents.present?

      usd = attribute_number(attrs, "cost_usd")
      return (usd * 100).round(6) if usd.present?

      0.0
    end

    def extract_terminal_session_token(attrs, resource_attrs)
      value = attribute_string(attrs, "terminal_session_token")
      value ||= attribute_string(resource_attrs, "terminal_session_token")

      normalize_terminal_session_token(value)
    end

    def attribute_string(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["stringValue"].to_s if value.key?("stringValue")
        return value["intValue"].to_s if value.key?("intValue")
        return value["doubleValue"].to_s if value.key?("doubleValue")
      end

      nil
    end

    def attribute_number(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["intValue"].to_f if value.key?("intValue")
        return value["doubleValue"].to_f if value.key?("doubleValue")
        return value["stringValue"].to_f if value.key?("stringValue")
      end

      nil
    end

    def normalize_terminal_session_token(raw)
      token = raw.to_s.strip
      return nil if token.blank?

      token
    end
  end
end
