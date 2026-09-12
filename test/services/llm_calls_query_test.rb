# frozen_string_literal: true

require "test_helper"

class LlmCallsQueryTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner   = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @run     = create(:workflow_run, project: @project, user: @owner)

    @workflow = create(:workflow, scope: @project)
    @step     = create(:step, workflow: @workflow)
    @step_run = create(:step_run, workflow_run: @run, step: @step)

    @session  = create(:terminal_session, :agent_session, user: @owner, project: @project)

    @call1 = create(:llm_call, workflow_run: @run, step_run: @step_run,
                                terminal_session: @session, model: "claude-sonnet-4-5",
                                occurred_at: 3.hours.ago, total_cents_precise: "0.05")
    @call2 = create(:llm_call, workflow_run: @run, step_run: @step_run,
                                terminal_session: @session, model: "claude-haiku-4-5",
                                occurred_at: 2.hours.ago, total_cents_precise: "0.01")
    @call3 = create(:llm_call, terminal_session: create(:terminal_session, :agent_session,
                                                         user: @owner, project: @project),
                                model: "claude-sonnet-4-5", occurred_at: 1.hour.ago)
  end

  # --- root scope ---

  test "scopes to workflow_run" do
    result = LlmCallsQuery.new(workflow_run: @run).scope
    assert_includes result, @call1
    assert_includes result, @call2
    assert_not_includes result, @call3
  end

  test "scopes to terminal_session" do
    result = LlmCallsQuery.new(terminal_session: @session).scope
    assert_includes result, @call1
    assert_includes result, @call2
    assert_not_includes result, @call3
  end

  # --- filters ---

  test "filters by step_run_id" do
    other_step_run = create(:step_run, workflow_run: @run,
                                       step: create(:step, workflow: @workflow))
    call4 = create(:llm_call, workflow_run: @run, step_run: other_step_run,
                               terminal_session: @session, model: "gpt-4o",
                               occurred_at: 30.minutes.ago)

    result = LlmCallsQuery.new(workflow_run: @run, step_run_id: @step_run.id).scope
    assert_includes result, @call1
    assert_not_includes result, call4
  end

  test "filters by model" do
    result = LlmCallsQuery.new(workflow_run: @run, model: "claude-sonnet-4-5").scope
    assert_includes result, @call1
    assert_not_includes result, @call2
  end

  test "filters by date_from" do
    result = LlmCallsQuery.new(workflow_run: @run, date_from: 2.5.hours.ago).scope
    assert_includes result, @call2
    assert_not_includes result, @call1
  end

  test "filters by date_to" do
    result = LlmCallsQuery.new(workflow_run: @run, date_to: 2.5.hours.ago).scope
    assert_includes result, @call1
    assert_not_includes result, @call2
  end

  test "filters combine: model + date_from" do
    result = LlmCallsQuery.new(workflow_run: @run,
                                model: "claude-sonnet-4-5",
                                date_from: 4.hours.ago).scope
    assert_includes result, @call1
    assert_not_includes result, @call2
  end

  # --- sort ---

  test "default sort is occurred_at desc" do
    ids = LlmCallsQuery.new(workflow_run: @run).scope.pluck(:id)
    assert_equal [ @call2.id, @call1.id ], ids
  end

  test "sort by total_cents_precise desc" do
    ids = LlmCallsQuery.new(workflow_run: @run, sort: "cost_desc").scope.pluck(:id)
    assert_equal [ @call1.id, @call2.id ], ids
  end
end
