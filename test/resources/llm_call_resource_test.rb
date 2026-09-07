# frozen_string_literal: true

require "test_helper"

class LlmCallResourceTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @owner    = create(:user, company: @company)
    @project  = create(:project, company: @company, owner: @owner)
    @run      = create(:workflow_run, project: @project, user: @owner)
    @workflow = create(:workflow, scope: @project)
    @step     = create(:step, workflow: @workflow, name: "Post report")
    @step_run = create(:step_run, workflow_run: @run, step: @step)
    @session  = create(:terminal_session, :agent_session, user: @owner, project: @project)
    @call     = create(:llm_call,
                        workflow_run: @run,
                        step_run: @step_run,
                        terminal_session: @session,
                        model: "claude-sonnet-4-5",
                        input_tokens: 1200,
                        output_tokens: 450,
                        cache_read_tokens: 100,
                        cache_write_tokens: 50,
                        total_cents_precise: "0.04512300",
                        source: "otlp",
                        occurred_at: Time.utc(2026, 8, 28, 10, 0, 0))
  end

  test "serializes all expected keys" do
    hash = LlmCallResource.new(@call).to_h
    expected_keys = %w[id model inputTokens outputTokens cacheReadTokens cacheWriteTokens
                       costCents occurredAt stepRunId stepName source]
    assert_equal expected_keys.sort, hash.keys.sort
  end

  test "costCents rounds total_cents_precise to 4 decimal places" do
    hash = LlmCallResource.new(@call).to_h
    assert_in_delta(0.0451, hash["costCents"])
  end

  test "stepName is populated from the associated step" do
    hash = LlmCallResource.new(@call).to_h
    assert_equal "Post report", hash["stepName"]
  end

  test "stepName is nil when step_run is absent" do
    call = create(:llm_call, terminal_session: @session, model: "claude-sonnet-4-5",
                              source: "otlp", occurred_at: Time.current)
    hash = LlmCallResource.new(call).to_h
    assert_nil hash["stepName"]
  end

  test "occurredAt is an ISO8601 string" do
    hash = LlmCallResource.new(@call).to_h
    assert_equal "2026-08-28T10:00:00.000Z", hash["occurredAt"]
  end
end
