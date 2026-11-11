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
      @user = create(:user, :admin, company: company)
      @project = create(:project, company: company, owner: @user)
      @session = create_session
    end

    # The mock answers in each vendor's own convention: Anthropic counts cached input apart
    # from input, OpenAI and Gemini count it inside. Every adapter hands on uncached input.
    # The capture runs with both exporters on (bin/capture-agent-otlp), so one run is read
    # both ways: a session exports logs only now, and its usage must equal what the metrics
    # of the same run said. The mock asks for one Read first, so there are two requests.
    test "Claude Code's api_request logs, one call per request, equal to its metrics" do
      from_logs = ingest(ClaudeCodeAdapter.new, "claude_code", only: "resourceLogs")
      from_metrics = ingest(ClaudeCodeAdapter.new, "claude_code", only: "resourceMetrics",
                                                                    session: create_session)

      assert_equal [ 2 * INPUT, 2 * OUTPUT, 2 * CACHE_READ, 10 ],
                   [ from_logs.input_tokens, from_logs.output_tokens, from_logs.cache_read_tokens,
                     from_logs.cache_write_tokens ]
      %i[input_tokens output_tokens cache_read_tokens cache_write_tokens].each do |column|
        assert_equal from_metrics.public_send(column), from_logs.public_send(column), column
      end
      assert_in_delta from_metrics.total_cents_precise.to_f, from_logs.total_cents_precise.to_f, 0.000001
      assert_equal [ "claude-sonnet-4-5" ], from_logs.models

      row = { model: "claude-sonnet-4-5", provider: "anthropic", source: "otlp_log", granularity: "request",
              cost_basis: "reported", input_tokens: INPUT, output_tokens: OUTPUT, cache_read_tokens: CACHE_READ,
              cache_write_tokens: 5 }
      assert_calls [ row, row ]
      assert_equal 1, LlmCall.where(terminal_session: @session).distinct.count(:prompt_ref)
    end

    test "Claude Code's prompt and tool call, recorded for a project that shares prompts" do
      @session.project.update!(settings: { "insights" => { "share_prompts" => true } })

      ingest(ClaudeCodeAdapter.new, "claude_code", only: "resourceLogs")

      prompt = AgentPrompt.find_by!(terminal_session: @session)
      assert_equal "Read capture.txt, then say hi. CAPTURE_TOOL", prompt.text
      call = AgentToolCall.find_by!(terminal_session: @session)
      assert_equal [ "Read", { "file_path" => "/tmp/capture.txt" }, true ], [ call.tool_name, call.arguments, call.success ]
      assert_equal prompt.prompt_ref, call.prompt_ref
    end

    test "Claude Code's prompts are not kept for a project that does not share them" do
      ingest(ClaudeCodeAdapter.new, "claude_code", only: "resourceLogs")

      assert_not AgentPrompt.exists?(terminal_session: @session)
      assert_not AgentToolCall.exists?(terminal_session: @session)
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

    def create_session
      create(:terminal_session, :running, user: @user, project: @project)
    end

    # only: the payload kind to replay ("resourceLogs", "resourceMetrics"), all when nil.
    def ingest(adapter, runtime_id, only: nil, session: @session)
      version = AgentRuntime.fetch(runtime_id).cli_version
      fixture = Rails.root.join("test/fixtures/files/otlp/#{runtime_id}-#{version}.json")
      assert fixture.file?, "no OTLP capture for #{runtime_id} #{version}: run bin/capture-agent-otlp #{runtime_id}"

      payloads = JSON.parse(fixture.read.gsub("OTLP_CAPTURE_TOKEN", session.route_token))
      payloads = payloads.select { |payload| payload.key?(only) } if only
      session.update!(agent_type: runtime_id)
      payloads.each { |payload| adapter.ingest_usage(payload, session) }
      session.reload.usage_statistic
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
