# frozen_string_literal: true

require "test_helper"

# The reconciler is tested through its outcomes on real rows (docs/testing.md §2,
# service layer): what the gate's status/resolution_data/audit trail say afterwards,
# and whether the column auto-trigger became eligible again. Only the CI provider
# boundary is faked — via Ci::GateProbe, the app-owned seam the reconciler asks.
class GateReconcilerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    @repository = create(:repository, full_name: "org/app", scope: @project, integration: @integration)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
  end

  # == provider says the run finished ==

  test "resolves a gate with the conclusion the provider reports" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.completed("success", "2 check suites completed"))

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:resolved]
    assert gate.resolved?
    assert_equal "success", gate.conclusion
    assert_equal "reconciliation", gate.resolution_data["source"]
    assert_not_nil gate.resolved_at
  end

  test "records a failing conclusion as a failure instead of bypassing it" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.completed("failure", "1 check suite failed"))

    GateReconciler.reconcile_all

    gate.reload
    assert_equal "failed", gate.ci_status
    assert_equal "failure", gate.conclusion
    assert_not gate.passed?
  end

  test "records a resolved-by-reconciliation gate on the board activity feed" do
    create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.completed("success"))

    assert_difference -> { BoardActivity.where(event_type: "gate_reconciled").count }, 1 do
      GateReconciler.reconcile_all
    end

    activity = BoardActivity.where(event_type: "gate_reconciled").last
    assert_equal "system", activity.actor_type
    assert_equal @task.id, activity.board_task_id
  end

  test "resolves a gitlab gate under the status key its webhook path uses" do
    gitlab_integration = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    create(:repository, full_name: "group/app", scope: @project, integration: gitlab_integration,
                        clone_url: "https://gitlab.com/group/app.git")
    gate = create_gate(
      created_at: 1.hour.ago,
      gate_type: :gitlab_pipeline_completed,
      metadata: { "repo_full_name" => "group/app", "pipeline_id" => 555 }
    )
    stub_probe(Ci::ProbeResult.completed("success", "pipeline 555 finished as success"))

    GateReconciler.reconcile_all

    gate.reload
    assert_equal "success", gate.resolution_data["status"]
    assert_equal "succeeded", gate.ci_status
  end

  # == provider says it is still running ==

  test "leaves a still-running gate pending and stamps the probe on it" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.in_progress("1/2 check suites still running"))

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:waiting]
    assert gate.pending?
    assert_equal 1, gate.reconcile_attempts
    assert_equal "in_progress", gate.reconciliation_log.first["outcome"]
    assert_not_nil gate.last_reconciled_at
  end

  test "does not probe a gate that is still inside its grace window" do
    gate = create_gate(created_at: 1.minute.ago)
    Ci::GateProbe.expects(:new).never

    counts = GateReconciler.reconcile_all

    assert_equal 0, counts[:checked]
    assert gate.reload.pending?
  end

  # == TTL ==

  test "marks a gate stale once its TTL runs out with the provider still running" do
    gate = create_gate(created_at: 20.hours.ago, expires_at: 8.hours.ago)
    stub_probe(Ci::ProbeResult.in_progress("still running"))

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:stale]
    assert gate.stale?
    assert_equal "stale", gate.ci_status
    assert_match(/no CI result after/, gate.diagnostic_reason)
    assert_equal "stale", gate.resolution_data["outcome"]
    assert_nil gate.conclusion
    assert_nil gate.resolved_at
  end

  test "marks a gate stale when the provider cannot be read past the TTL" do
    gate = create_gate(created_at: 20.hours.ago, expires_at: 8.hours.ago)
    stub_probe(Ci::ProbeResult.unavailable("Octokit::TooManyRequests: rate limited"))

    GateReconciler.reconcile_all

    assert gate.reload.stale?
    assert_match(/rate limited/, gate.reconciliation_log.first["detail"])
  end

  test "keeps probing an unreadable gate that is still inside its TTL" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.unavailable("Octokit::TooManyRequests: rate limited"))

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:waiting]
    assert gate.pending?
    assert_equal "unavailable", gate.reconciliation_log.first["outcome"]
  end

  # == unresolvable ==

  test "marks an unresolvable gate stale immediately, without waiting out its TTL" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.unresolvable("PR #42 not found in org/app"))

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:stale]
    assert gate.stale?
    assert_not gate.expired?
    assert_match(/cannot be read/, gate.diagnostic_reason)
    assert_match(/PR #42 not found/, gate.diagnostic_reason)
  end

  test "escalates a stale gate onto the board activity feed with its reason" do
    create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.unresolvable("PR #42 not found in org/app"))

    assert_difference -> { BoardActivity.where(event_type: "gate_stale").count }, 1 do
      GateReconciler.reconcile_all
    end

    activity = BoardActivity.where(event_type: "gate_stale").last
    assert_equal "system", activity.actor_type
    assert_match(/PR #42 not found/, activity.metadata["reason"])
  end

  # == effect on the task's automation ==

  test "staling the last gate releases the column auto-trigger the gate was holding" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.unresolvable("workflow run 99 not found in org/app"))

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: @task, mode: :non_interactive)
    ).once

    GateReconciler.reconcile_all

    assert_equal 0, @task.gates.pending.count
    assert_equal 1, @task.gates.stale.count
  end

  test "a task with another pending gate stays blocked when one gate goes stale" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    create_gate(created_at: 1.hour.ago)
    create_gate(created_at: 1.minute.ago, metadata: { "repo_full_name" => "org/app", "pr_number" => 43 })
    stub_probe(Ci::ProbeResult.unresolvable("PR #42 not found in org/app"))

    WorkflowService.expects(:start).never

    GateReconciler.reconcile_all

    assert_equal 1, @task.gates.pending.count
  end

  # == sweep mechanics ==

  test "the batch size caps how many gates one sweep probes" do
    3.times { |i| create_gate(created_at: (i + 1).hours.ago, metadata: { "repo_full_name" => "org/app", "pr_number" => 50 + i }) }
    stub_probe(Ci::ProbeResult.completed("success"))

    counts = GateReconciler.reconcile_all(limit: 2)

    assert_equal 2, counts[:checked]
    assert_equal 1, @task.gates.pending.count
  end

  test "one failing gate does not abort the sweep" do
    Rails.logger.stubs(:error)
    create_gate(created_at: 2.hours.ago)
    create_gate(created_at: 1.hour.ago, metadata: { "repo_full_name" => "org/app", "pr_number" => 43 })

    probe = mock("probe")
    probe.stubs(:call).raises(RuntimeError, "boom").then.returns(Ci::ProbeResult.completed("success"))
    Ci::GateProbe.stubs(:new).returns(probe)

    counts = GateReconciler.reconcile_all

    assert_equal 2, counts[:checked]
    assert_equal 1, counts[:errors]
    assert_equal 1, counts[:resolved]
  end

  test "returns zeroed counts when nothing is due" do
    counts = GateReconciler.reconcile_all

    assert_equal({ checked: 0, resolved: 0, stale: 0, waiting: 0, skipped: 0, errors: 0 }, counts.except(:elapsed))
  end

  # == races: the sweep is not the only writer ==
  #
  # A provider call takes real time, and the gate's own webhook (plus a retried or
  # overlapping second sweeper) can reach a terminal state during it. The claim is
  # durable and every transition is a compare-and-set on a still-pending row, so a
  # probe that comes back late is discarded rather than applied.

  test "does not overwrite a webhook verdict that lands while the provider is being probed" do
    gate = create_gate(created_at: 20.hours.ago, expires_at: 8.hours.ago)

    # The gate's real webhook arrives mid-probe and records the provider's failure.
    # Without the pending re-check, the TTL branch below would then bury it as stale.
    stub_probe(Ci::ProbeResult.in_progress("still running")) do
      GateService.resolve_github_checks(repo_full_name: "org/app", pr_number: 42, conclusion: "failure")
    end

    counts = GateReconciler.reconcile_all

    gate.reload
    assert_equal 1, counts[:skipped]
    assert_equal 0, counts[:stale]
    assert gate.resolved?
    assert_equal "failure", gate.conclusion
    assert_equal "failed", gate.ci_status
    assert_nil gate.diagnostic_reason
    assert_equal 0, BoardActivity.where(event_type: "gate_stale").count
    assert_equal "superseded:resolved", gate.reconciliation_log.first["outcome"]
  end

  test "a second sweeper that probed the same gate records neither a second resolution nor a second activity" do
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.completed("success"))

    # Two drainers holding their own copy of the row, both already past the probe.
    first_worker = Gate.find(gate.id)
    second_worker = Gate.find(gate.id)

    assert_difference -> { BoardActivity.where(event_type: "gate_reconciled").count }, 1 do
      assert_equal :resolved, GateReconciler.reconcile(first_worker)
      assert_equal :skipped, GateReconciler.reconcile(second_worker)
    end

    gate.reload
    assert gate.resolved?
    assert_equal "success", gate.conclusion
    assert_equal "superseded:resolved", gate.reconciliation_log.first["outcome"]
  end

  test "two sweepers finishing the same gate dispatch the column auto-trigger once" do
    workflow = create(:workflow, scope: @project)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, trigger_mode: :auto, cooldown_seconds: 0)
    gate = create_gate(created_at: 1.hour.ago)
    stub_probe(Ci::ProbeResult.unresolvable("PR #42 not found in org/app"))

    WorkflowService.expects(:start).with(
      has_entries(workflow: workflow, task: @task, mode: :non_interactive)
    ).once

    assert_equal :stale, GateReconciler.reconcile(Gate.find(gate.id))
    assert_equal :skipped, GateReconciler.reconcile(Gate.find(gate.id))
  end

  test "claiming is durable, so a probe that raises does not hand the gate to the next sweeper" do
    Rails.logger.stubs(:error)
    gate = create_gate(created_at: 1.hour.ago)
    probe = mock("probe")
    probe.stubs(:call).raises(RuntimeError, "boom")
    Ci::GateProbe.stubs(:new).returns(probe)

    first = GateReconciler.reconcile_all

    assert_equal 1, first[:errors]
    # The claim, not an outcome stamp: the probe never returned, so nothing was
    # recorded on the gate — but the row is out of the due set all the same.
    assert_not_nil gate.reload.last_reconciled_at
    assert_equal 0, gate.reconcile_attempts
    assert_empty Array(gate.reconciliation_log)

    second = GateReconciler.reconcile_all

    assert_equal 0, second[:checked]
    assert gate.reload.pending?
  end

  private

  def create_gate(**attrs)
    @task.gates.create!({
      gate_type: :github_checks_completed,
      metadata: { "repo_full_name" => "org/app", "pr_number" => 42 },
      creator: @user
    }.merge(attrs))
  end

  # The CI provider is the only faked boundary: the probe is app-owned, returns an
  # app-owned value object, and every adapter behind it has its own contract test.
  #
  # An optional block runs INSIDE the probe, which is how the race tests land a
  # competing write in the window the sweep is waiting on the provider.
  def stub_probe(result, &during_probe)
    probe = Object.new
    probe.define_singleton_method(:call) do
      during_probe&.call
      result
    end
    Ci::GateProbe.stubs(:new).returns(probe)
  end
end
