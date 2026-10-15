# frozen_string_literal: true

require "test_helper"

# What each pinned agent CLI really exports over OTLP, captured with bin/capture-agent-otlp:
# the CLI answers one prompt against a canned model reply (test/otlp_capture/mock.py) and its
# telemetry goes through docker/otlp-ingest as it does in a session. A fixture is named after
# the pin in config/agent_runtimes.json, so raising a pin without re-capturing fails here —
# before a renamed metric or attribute zeroes production usage.
module Agents
  class OtlpContractTest < ActiveSupport::TestCase
    # The canned reply's token counts (test/otlp_capture/mock.py).
    INPUT = 120
    OUTPUT = 7
    CACHE_READ = 30

    SUPPORTED_INSIGHTS_METADATA = {
      "claude_code" => ClaudeCodeAdapter,
      "codex" => CodexAdapter,
      "gemini_cli" => GeminiCliAdapter,
      "kiro_cli" => KiroCliAdapter
    }.freeze
    EXCLUDED_INSIGHTS_METADATA = {
      "cursor_cli" => CursorCliAdapter,
      "antigravity_cli" => AntigravityCliAdapter,
      "grok" => GrokAdapter
    }.freeze

    setup do
      company = create(:company)
      user = create(:user, :admin, company: company)
      project = create(:project, company: company, owner: user)
      @session = create(:terminal_session, :running, user: user, project: project)
      @insights = create(:integration, :insights, :active, company: company,
                                                           project: project, connected_by: user)
    end

    test "only the four supported runtimes receive active Insights resource metadata" do
      SUPPORTED_INSIGHTS_METADATA.each do |runtime_id, adapter_class|
        @session.update!(agent_type: runtime_id)
        raw = adapter_class.new.default_env_vars(@session)["OTEL_RESOURCE_ATTRIBUTES"]
        attributes = decode_resource_attributes(raw)

        assert_equal "true", attributes["proxy_enabled"], runtime_id
        assert_equal @session.user.email, attributes["user_email"], runtime_id
        assert_equal @session.project.name, attributes["project_name"], runtime_id
        refute_includes attributes.keys, "project_id", runtime_id
        refute_includes raw, @insights.insights_ingest_token, runtime_id
      end
    end

    test "Cursor Antigravity and Grok never receive Insights resource metadata" do
      EXCLUDED_INSIGHTS_METADATA.each do |runtime_id, adapter_class|
        @session.update!(agent_type: runtime_id)
        raw = adapter_class.new.default_env_vars(@session)["OTEL_RESOURCE_ATTRIBUTES"]
        attributes = decode_resource_attributes(raw)

        Insights::RuntimeResourceAttributes::INSIGHTS_KEYS.each do |key|
          refute_includes attributes.keys, key, "#{runtime_id} unexpectedly received #{key}"
        end
      end

      @session.update!(agent_type: "grok")
      grok_attributes = decode_resource_attributes(GrokAdapter.new.default_env_vars(@session)["OTEL_RESOURCE_ATTRIBUTES"])
      assert_equal @session.route_token, grok_attributes["terminal_session_token"],
                   "Grok keeps Rails internal usage routing only"
    end

    test "Claude Code's token and cost metrics" do
      stat = ingest(ClaudeCodeAdapter.new, "claude_code")

      assert_equal INPUT, stat.input_tokens
      assert_equal OUTPUT, stat.output_tokens
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal 5, stat.cache_write_tokens
      assert_operator stat.total_cents_precise, :>, 0
      assert_equal [ "claude-sonnet-4-5" ], stat.models
    end

    test "Codex's response.completed event" do
      stat = ingest(CodexAdapter.new, "codex")

      assert_equal INPUT, stat.input_tokens
      assert_equal OUTPUT, stat.output_tokens
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal [ "gpt-5" ], stat.models
    end

    test "Gemini CLI's api_response events, counted once beside its cumulative metric" do
      stat = ingest(GeminiCliAdapter.new, "gemini_cli")

      assert_equal INPUT, stat.input_tokens
      assert_equal OUTPUT + 2, stat.output_tokens, "thought tokens count as output"
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal [ "gemini-2.5-pro" ], stat.models
    end

    private

    def decode_resource_attributes(raw)
      return {} if raw.blank?

      raw.split(",").to_h do |pair|
        key, value = pair.split("=", 2)
        [ key, URI.decode_uri_component(value) ]
      end
    end

    def ingest(adapter, runtime_id)
      version = AgentRuntime.fetch(runtime_id).cli_version
      fixture = Rails.root.join("test/fixtures/files/otlp/#{runtime_id}-#{version}.json")
      assert fixture.file?, "no OTLP capture for #{runtime_id} #{version}: run bin/capture-agent-otlp #{runtime_id}"

      payloads = JSON.parse(fixture.read.gsub("OTLP_CAPTURE_TOKEN", @session.route_token))
      payloads.each { |payload| adapter.ingest_usage(payload, @session) }
      @session.reload.usage_statistic
    end
  end
end
