# frozen_string_literal: true

require "test_helper"

class Runners::ResolverTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user, name: "Payments")
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
    @run = create(:workflow_run, workflow: create(:workflow, scope: @project), project: @project, user: @user)
  end

  test "a record without a runner is hosted, read without the flag" do
    Feature.expects(:enabled?).never

    assert_nil Runners::Resolver.resolve!(@run)
  end

  test "a runner that passes every check is still refused in phase 1" do
    @run.update!(runner: @runner)

    refusal = with_feature(:external_runners, true, company: @company) { refusal_for(@run) }

    assert_equal "runner_execution_not_enabled", refusal.reason
    assert_equal "Runner \"Prod VPC\" can't take sessions yet: runner execution not enabled.", refusal.message
  end

  test "without the flag for the company the runner is unavailable" do
    @run.update!(runner: @runner)

    refusal = with_feature(:external_runners, false, company: @company) { refusal_for(@run) }

    assert_equal "runner_unavailable", refusal.reason
    assert_equal "External runners are not enabled for this company.", refusal.message
  end

  test "a deleted, disabled or revoked runner is unavailable, named, with what to do" do
    @run.update!(runner: @runner)

    messages = with_feature(:external_runners, true, company: @company) do
      @runner.disable!
      disabled = refusal_for(@run.reload)
      @runner.revoke!
      revoked = refusal_for(@run.reload)
      @runner.soft_delete!
      [ disabled, revoked, refusal_for(@run.reload) ]
    end

    assert_equal %w[runner_unavailable] * 3, messages.map(&:reason)
    assert_equal [
      "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner on the workflow.",
      "Runner \"Prod VPC\" is revoked. Pick another runner on the workflow.",
      "Runner \"Prod VPC\" is deleted. Pick another runner on the workflow."
    ], messages.map(&:message)
  end

  test "a runner the project can no longer see is forbidden" do
    other = create(:project, company: @company, owner: @user)
    @runner.update!(project: other)
    @run.update_column(:runner_id, @runner.id)

    refusal = with_feature(:external_runners, true, company: @company) { refusal_for(@run) }

    assert_equal "runner_forbidden", refusal.reason
    assert_equal "Runner #{@runner.id} is not available to project Payments.", refusal.message
  end

  test "a stale id that names another company's runner is forbidden without reading that runner" do
    foreign = create(:runner, name: "Their VPC")
    @run.update_column(:runner_id, foreign.id)

    refusal = with_feature(:external_runners, true, company: @company) { refusal_for(@run.reload) }

    assert_equal "runner_forbidden", refusal.reason
    assert_equal "Runner #{foreign.id} is not available to project Payments.", refusal.message
    assert_not_includes refusal.message, "Their VPC"
  end

  test "a standalone session is told to pick another runner for the session" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project, mode: "non_interactive",
                                                        initial_prompt: "go", runner: @runner)
    @runner.disable!

    refusal = with_feature(:external_runners, true, company: @company) do
      assert_raises(Runners::Resolver::Refused) { Runners::Resolver.resolve!(session, pick_from: "for the session") }
    end

    assert_equal "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner for the session.", refusal.message
  end

  private

  def refusal_for(record)
    assert_raises(Runners::Resolver::Refused) { Runners::Resolver.resolve!(record) }
  end
end
