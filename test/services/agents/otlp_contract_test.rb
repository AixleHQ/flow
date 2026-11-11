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

    setup do
      company = create(:company)
      user = create(:user, :admin, company: company)
      project = create(:project, company: company, owner: user)
      @session = create(:terminal_session, :running, user: user, project: project)
    end

    # The mock answers in each vendor's own convention: Anthropic counts cached input apart
    # from input, OpenAI and Gemini count it inside. Every adapter hands on uncached input.
    test "Claude Code's token and cost metrics" do
      stat = ingest(ClaudeCodeAdapter.new, "claude_code")

      assert_equal INPUT, stat.input_tokens
      assert_equal OUTPUT, stat.output_tokens
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal 5, stat.cache_write_tokens
      assert_operator stat.total_cents_precise, :>, 0
      assert_equal [ "claude-sonnet-4-5" ], stat.models

      assert_calls [ { model: "claude-sonnet-4-5", provider: "anthropic", source: "otlp_metric", granularity: "batch",
                       cost_basis: "reported", input_tokens: INPUT, output_tokens: OUTPUT,
                       cache_read_tokens: CACHE_READ, cache_write_tokens: 5 } ]
    end

    test "Codex's response.completed event" do
      stat = ingest(CodexAdapter.new, "codex")

      assert_equal INPUT - CACHE_READ, stat.input_tokens
      assert_equal OUTPUT, stat.output_tokens
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal [ "gpt-5" ], stat.models

      assert_calls [ { model: "gpt-5", provider: "openai", source: "otlp_log", granularity: "request",
                       cost_basis: "priced", input_tokens: INPUT - CACHE_READ, output_tokens: OUTPUT,
                       cache_read_tokens: CACHE_READ, cache_write_tokens: 0 } ]
    end

    test "Gemini CLI's api_response events, counted once beside its cumulative metric" do
      stat = ingest(GeminiCliAdapter.new, "gemini_cli")

      assert_equal INPUT - CACHE_READ, stat.input_tokens
      assert_equal OUTPUT + 2, stat.output_tokens, "thought tokens count as output"
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal [ "gemini-2.5-pro" ], stat.models

      assert_calls [ { model: "gemini-2.5-pro", provider: "google", source: "otlp_log", granularity: "request",
                       cost_basis: "priced", input_tokens: INPUT - CACHE_READ, output_tokens: OUTPUT + 2,
                       cache_read_tokens: CACHE_READ, cache_write_tokens: 0, duration_ms: 93 } ]
    end

    # Captured offline against the mock (a custom provider), so the span carries the token
    # counts but not the AI credits GitHub's routing adds; CopilotCliAdapterTest prices those.
    test "Copilot CLI's chat span, with the cached tokens counted apart" do
      stat = ingest(CopilotCliAdapter.new, "copilot_cli")

      assert_equal INPUT, stat.input_tokens
      assert_equal OUTPUT, stat.output_tokens
      assert_equal CACHE_READ, stat.cache_read_tokens
      assert_equal 5, stat.cache_write_tokens
      assert_equal [ "claude-sonnet-4-5" ], stat.models

      assert_calls [ { model: "claude-sonnet-4-5", provider: "github_copilot", source: "otlp_span",
                       granularity: "request", cost_basis: "unknown", input_tokens: INPUT, output_tokens: OUTPUT,
                       cache_read_tokens: CACHE_READ, cache_write_tokens: 5 } ]
    end

    private

    def ingest(adapter, runtime_id)
      version = AgentRuntime.fetch(runtime_id).cli_version
      fixture = Rails.root.join("test/fixtures/files/otlp/#{runtime_id}-#{version}.json")
      assert fixture.file?, "no OTLP capture for #{runtime_id} #{version}: run bin/capture-agent-otlp #{runtime_id}"

      payloads = JSON.parse(fixture.read.gsub("OTLP_CAPTURE_TOKEN", @session.route_token))
      @session.update!(agent_type: runtime_id)
      payloads.each { |payload| adapter.ingest_usage(payload, @session) }
      @session.reload.usage_statistic
    end

    # The llm_calls rows the captured telemetry yields: the record every consumer reads.
    def assert_calls(expected)
      LlmCalls::Materializer.call(@session)
      keys = expected.flat_map(&:keys).uniq
      actual = LlmCall.where(terminal_session: @session).order(:event_index).map { |call| call.slice(*keys).symbolize_keys }

      assert_equal expected.map { |row| keys.index_with { |key| row[key] } }, actual
      LlmCall.where(terminal_session: @session).find_each do |call|
        assert_equal call.cost_basis == "unknown", call.total_cents_precise.nil?, "cost of #{call.model}"
      end
    end
  end
end
