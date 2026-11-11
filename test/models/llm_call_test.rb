# frozen_string_literal: true

require "test_helper"

class LlmCallTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @owner    = create(:user, company: @company)
    @project  = create(:project, company: @company, owner: @owner)
    @run      = create(:workflow_run, project: @project, user: @owner)
    @session  = create(:terminal_session, :agent_session, user: @owner, project: @project)
    @call     = create(:llm_call, workflow_run: @run, terminal_session: @session,
                                  model: "claude-sonnet-4-5",
                                  occurred_at: 1.hour.ago)
    @other_session = create(:terminal_session, :agent_session, user: @owner, project: @project)
    @other_call    = create(:llm_call, terminal_session: @other_session,
                                       model: "gpt-4o", provider: "openai",
                                       occurred_at: 2.hours.ago)
  end

  test "for_workflow_run returns only calls belonging to the given run" do
    result = LlmCall.for_workflow_run(@run.id)
    assert_includes result, @call
    assert_not_includes result, @other_call
  end

  test "for_session returns only calls belonging to the given terminal session" do
    result = LlmCall.for_session(@session.id)
    assert_includes result, @call
    assert_not_includes result, @other_call
  end

  test "an unknown cost carries no amount" do
    call = build(:llm_call, terminal_session: @session, cost_basis: "unknown", total_cents_precise: 0)

    assert_not call.valid?
    assert_includes call.errors[:total_cents_precise], "must be blank"
  end

  test "the vocabulary is closed" do
    call = build(:llm_call, terminal_session: @session, source: "otlp", granularity: "minute", cost_basis: "guessed")

    assert_not call.valid?
    assert_equal %i[cost_basis granularity source], call.errors.attribute_names.sort
  end

  test "every call gets its own uid" do
    other = create(:llm_call, terminal_session: @session)

    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, @call.reload.uid)
    assert_not_equal @call.uid, other.reload.uid
  end
end
