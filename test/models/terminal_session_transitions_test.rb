# frozen_string_literal: true

require "test_helper"

class TerminalSessionTransitionsTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, company: @user.companies.first, owner: @user)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, :running, workflow_run: run, step: create(:step, workflow: workflow))
    @session = create(:terminal_session, :running, session_type: "workflow_step", user: @user, project: @project,
                                                   step_run: @step_run, container_id: "c-1")
  end

  test "a step session's failure wakes its run once the failure is committed" do
    WorkflowService.expects(:notify_container_finished).with { TerminalSession.find(@session.id).failed? }.once

    @session.fail!
  end

  test "a step session's finish wakes its run once the finish is committed" do
    @session.start_finishing!
    WorkflowService.expects(:notify_container_finished).with { TerminalSession.find(@session.id).finished? }.once

    @session.finish!
  end

  test "a step session's cancellation wakes its run once the cancel is committed" do
    WorkflowService.expects(:notify_container_finished).with { TerminalSession.find(@session.id).cancelled? }.once

    @session.cancel!
  end

  test "the sessions of a run being stopped do not wake it again" do
    @step_run.workflow_run.update!(stop_requested_at: Time.current)
    WorkflowService.expects(:notify_container_finished).never

    @session.cancel!
  end

  test "a failure that rolls back wakes nobody" do
    WorkflowService.expects(:notify_container_finished).never

    TerminalSession.transaction do
      @session.fail!
      raise ActiveRecord::Rollback
    end

    assert_equal "running", @session.reload.state
  end

  test "an ending is written in the same save as its state" do
    @session.fail!

    @session.reload
    assert_equal "failed", @session.state
    assert_not_nil @session.finished_at
    assert_nil @session.container_id
  end

  test "a cancelled session records the usage it ran up and keeps its container for teardown" do
    UsageStatistic.create!(terminal_session: @session, cost_cents: 250, input_tokens: 900, output_tokens: 100,
                           cache_write_tokens: 0, cache_read_tokens: 0, tokens: 1000)

    @session.cancel!

    @session.reload
    assert_equal "cancelled", @session.state
    assert_equal 250, @session.cost_cents
    assert_equal "c-1", @session.container_id
    assert_not_nil @session.finished_at
  end

  test "only a session that has not started can be queued" do
    fresh = create(:terminal_session, :agent_session, user: @user, project: @project)

    fresh.enqueue!

    assert_equal "queued", fresh.reload.state
    assert_not_nil fresh.queued_at
    assert_raises(AASM::InvalidTransition) { @session.enqueue! }
  end
end
