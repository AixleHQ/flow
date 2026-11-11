# frozen_string_literal: true

require "test_helper"

module LlmCalls
  class MaterializerTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @owner = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @owner)
    end

    test "each usage event becomes one call, in the canonical vocabulary" do
      session = session_with("claude_code", [
        event(model: "claude-sonnet-4-5", ts: "1768478400000", input: 120, output: 7, cache_read: 30, cache_write: 5,
              cents: 0.25, basis: "reported", source: "otlp")
      ])

      assert_equal 1, Materializer.call(session)

      call = LlmCall.find_by!(terminal_session: session)
      assert_equal 0, call.event_index
      assert_equal "claude-sonnet-4-5", call.model
      assert_equal "anthropic", call.provider
      assert_equal [ 120, 7, 30, 5 ], [ call.input_tokens, call.output_tokens, call.cache_read_tokens, call.cache_write_tokens ]
      assert_in_delta 0.25, call.total_cents_precise.to_f
      assert_equal %w[reported batch otlp_metric], [ call.cost_basis, call.granularity, call.source ]
      assert_equal Time.zone.at(1_768_478_400), call.occurred_at
      assert call.uid.present?
    end

    test "running again adds only the events that arrived since, and keeps every existing call as it was" do
      session = session_with("codex", [ event(input: 90, cache_read: 30, cents: 0.5, basis: "priced", source: "otlp") ])
      Materializer.call(session)
      first = LlmCall.find_by!(terminal_session: session)

      late = event(input: 10, cents: 0.1, basis: "priced", source: "otlp")
      session.usage_statistic.update!(events_data: session.usage_statistic.events_data + [ late ])

      assert_equal 1, Materializer.call(session)
      assert_equal 0, Materializer.call(session)
      assert_equal [ 0, 1 ], LlmCall.where(terminal_session: session).order(:event_index).pluck(:event_index)
      assert_equal first.attributes, first.reload.attributes
    end

    test "a workflow step's calls carry the run and the step" do
      run = create(:workflow_run, project: @project, user: @owner)
      step_run = create(:step_run, workflow_run: run)
      session = session_with("codex", [ event(input: 1, basis: "unknown", source: "otlp") ])
      step_run.update!(terminal_session: session)

      Materializer.call(session.reload)

      call = LlmCall.find_by!(terminal_session: session)
      assert_equal run.id, call.workflow_run_id
      assert_equal step_run.id, call.step_run_id
    end

    test "an unknown cost is null, not zero" do
      session = session_with("codex", [ event(model: "mystery-model", input: 5, cents: nil, basis: "unknown", source: "otlp") ])

      Materializer.call(session)

      call = LlmCall.find_by!(terminal_session: session)
      assert_nil call.total_cents_precise
      assert_equal "unknown", call.cost_basis
    end

    test "a token count the runtime does not report stays null" do
      session = session_with("kiro_cli", [
        { "model" => "claude-sonnet-4.5", "timestamp" => "1768478400000", "tokenUsage" => { "totalCents" => 4.0 },
          "costBasis" => "credits", "creditsUsed" => 0.4, "creditRateUsd" => 0.1, "source" => "otlp_credits_consumed" }
      ])

      Materializer.call(session)

      call = LlmCall.find_by!(terminal_session: session)
      assert_nil call.input_tokens
      assert_nil call.output_tokens
      assert_equal %w[kiro credits turn otlp_credits], [ call.provider, call.cost_basis, call.granularity, call.source ]
    end

    test "events written before adapters stamped a cost basis are read by the old conventions" do
      session = session_with("codex", [
        # Codex counted cached input inside inputTokens and wrote 0 for a cost it never had.
        event(input: 120, cache_read: 30, cents: 0.0, source: "otlp"),
        event(input: 100, cache_read: 0, cents: 0.75, source: "mitm")
      ])
      kiro = session_with("kiro_cli", [
        { "creditsUsed" => 1.5, "creditRateUsd" => 0.1, "source" => "get_usage_limits_delta" }
      ])

      Materializer.call(session)
      Materializer.call(kiro)

      unpriced, priced = LlmCall.where(terminal_session: session).order(:event_index).to_a
      assert_equal 90, unpriced.input_tokens
      assert_nil unpriced.total_cents_precise
      assert_equal "unknown", unpriced.cost_basis
      assert_equal "priced", priced.cost_basis
      assert_in_delta 0.75, priced.total_cents_precise.to_f

      credits = LlmCall.find_by!(terminal_session: kiro)
      assert_in_delta 15.0, credits.total_cents_precise.to_f
      assert_equal %w[credits session vendor_api unknown], [ credits.cost_basis, credits.granularity, credits.source, credits.model ]
    end

    test "an event with no time of its own is placed at the end of the session" do
      session = session_with("antigravity_cli", [ event(ts: nil, input: 1, basis: "unknown", source: "antigravity_stream_json") ])
      session.update_columns(finished_at: Time.utc(2026, 11, 11, 9, 30))

      Materializer.call(session)

      assert_equal Time.utc(2026, 11, 11, 9, 30), LlmCall.find_by!(terminal_session: session).occurred_at
    end

    test "Bedrock calls are billed by AWS and stored under the model's own id" do
      session = session_with("claude_code", [
        event(model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", input: 1, cents: 0.1, basis: "reported", source: "otlp")
      ])

      Materializer.call(session)

      call = LlmCall.find_by!(terminal_session: session)
      assert_equal "aws_bedrock", call.provider
      assert_equal "claude-sonnet-4-5-20250929-v1:0", call.model
    end

    test "Cursor's dashboard records, which carry no source tag, are vendor API calls" do
      session = session_with("cursor_cli", [
        { "timestamp" => "1768478400000", "model" => "claude-4-sonnet", "costBasis" => "reported",
          "tokenUsage" => { "inputTokens" => 1000, "outputTokens" => 200, "totalCents" => 3.5 } }
      ])

      Materializer.call(session)

      call = LlmCall.find_by!(terminal_session: session)
      assert_equal %w[cursor vendor_api request reported], [ call.provider, call.source, call.granularity, call.cost_basis ]
    end

    test "an event its adapter does not describe is left out" do
      session = session_with("codex", [ event(input: 1, basis: "unknown", source: "something_new") ])

      assert_equal 0, Materializer.call(session)
    end

    test "a session without usage has nothing to materialize" do
      session = create(:terminal_session, :running, user: @owner, project: @project, agent_type: "codex")

      assert_equal 0, Materializer.call(session)
    end

    private

    def session_with(agent_type, events)
      session = create(:terminal_session, :running, user: @owner, project: @project, agent_type: agent_type)
      session.create_usage_statistic!(
        input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, cost_cents: 0,
        source: "test", events_count: events.size, events_data: events
      )
      session
    end

    def event(source:, model: "gpt-5", ts: "1768478400000", input: 0, output: 0, cache_read: 0, cache_write: 0,
              cents: nil, basis: nil)
      {
        "model" => model, "timestamp" => ts,
        "tokenUsage" => { "inputTokens" => input, "outputTokens" => output, "cacheReadTokens" => cache_read,
                          "cacheWriteTokens" => cache_write, "totalCents" => cents },
        "costBasis" => basis, "source" => source
      }.compact
    end
  end
end
