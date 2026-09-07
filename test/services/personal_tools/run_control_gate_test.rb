# frozen_string_literal: true

require "test_helper"

module PersonalTools
  # The personal MCP reaches the same four run-control actions the run screen
  # does, so it enforces the same rule: only the person who started a run (or a
  # company admin) may cancel it or steer its steps.
  #
  # trigger_task_workflow's `force` is deliberately NOT gated: it cancels a run
  # only as a step of relaunching a BOARD CARD's automation, which belongs to
  # the team rather than to whoever happened to start the previous attempt —
  # and repairing a card launched under the wrong account is exactly what it is
  # for (see PersonalTools::TriggerTaskWorkflowTest).
  class RunControlGateTest < ActiveSupport::TestCase
    setup do
      # TemporalService is the app-owned boundary to the Temporal gem — faked so
      # an ALLOWED call signals nothing instead of reaching a server.
      TemporalService.stubs(:workflow_open?).returns(true)
      TemporalService.stubs(:send_signal).returns({ ok: true })

      @company = create(:company)
      @owner = create(:user, :employee, company: @company, name: "Ada Lovelace")
      @teammate = create(:user, :employee, company: @company)
      @admin = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @owner)
      @project.add_collaborator(@teammate)
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow, position: 1)
      @run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @owner)
    end

    TOOLS = {
      "cancel_workflow_run" => CancelWorkflowRun,
      "approve_step_run" => ApproveStepRun,
      "retry_step_run" => RetryStepRun,
      "skip_step_run" => SkipStepRun
    }.freeze

    def run_tool(klass, user)
      klass.new(params: { project_id: @project.id, run_id: @run.id }, user: user).execute
    end

    TOOLS.each do |name, klass|
      test "#{name} refuses a teammate who did not start the run, naming its owner" do
        error = assert_raises(Base::UnauthorizedError) { run_tool(klass, @teammate) }

        assert_match(/Ada Lovelace/, error.message)
        assert_match(/only they or a company admin can control it/, error.message)
      end

      test "#{name} lets a company admin through" do
        assert_nothing_raised { run_tool(klass, @admin) }
      end
    end

    test "cancel_workflow_run leaves the run untouched when the caller is not its owner" do
      assert_raises(Base::UnauthorizedError) { run_tool(CancelWorkflowRun, @teammate) }

      assert_equal "running", @run.reload.state
    end

    test "a run of another project is not found rather than refused" do
      other_project = create(:project, company: @company, owner: @owner)
      other_project.add_collaborator(@teammate)

      assert_raises(Base::NotFoundError) do
        CancelWorkflowRun.new(params: { project_id: other_project.id, run_id: @run.id }, user: @teammate).execute
      end
    end
  end
end
