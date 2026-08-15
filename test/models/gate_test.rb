# frozen_string_literal: true

require "test_helper"

class GateTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  # == TTL ==

  test "a new gate gets a TTL deadline from the configured ttl_hours" do
    freeze_time do
      gate = create_gate

      assert_equal Time.current + Gate.ttl, gate.expires_at
      assert_not gate.expired?
    end
  end

  test "an explicit expires_at is kept" do
    deadline = 30.minutes.from_now.change(usec: 0)
    gate = create_gate(expires_at: deadline)

    assert_equal deadline, gate.expires_at
  end

  test "a gate is expired once its deadline has passed" do
    gate = create_gate(created_at: 2.hours.ago, expires_at: 1.hour.ago)

    assert gate.expired?
    assert_not gate.expired?(2.hours.ago)
  end

  test "age_seconds measures the wait from creation" do
    gate = create_gate(created_at: 90.minutes.ago)

    assert_in_delta 5400, gate.age_seconds, 2
  end

  # == reconcilable scope ==

  test "reconcilable picks up only pending CI gates past the grace window" do
    fresh = create_gate(created_at: 1.minute.ago)
    due = create_gate(created_at: 3.hours.ago)
    probed_recently = create_gate(created_at: 3.hours.ago, last_reconciled_at: 1.minute.ago)
    probed_long_ago = create_gate(created_at: 3.hours.ago, last_reconciled_at: 2.hours.ago)
    resolved = create_gate(created_at: 3.hours.ago, status: :resolved)
    already_stale = create_gate(created_at: 3.hours.ago, status: :stale)

    ids = Gate.reconcilable.pluck(:id)

    assert_includes ids, due.id
    assert_includes ids, probed_long_ago.id
    assert_not_includes ids, fresh.id
    assert_not_includes ids, probed_recently.id
    assert_not_includes ids, resolved.id
    assert_not_includes ids, already_stale.id
  end

  test "reconcilable returns the oldest gate first so a backlog drains in order" do
    newer = create_gate(created_at: 1.hour.ago)
    older = create_gate(created_at: 5.hours.ago)

    assert_equal [ older.id, newer.id ], Gate.reconcilable.pluck(:id)
  end

  test "unresolved covers pending and stale but not resolved gates" do
    pending_gate = create_gate
    stale = create_gate(status: :stale)
    create_gate(status: :resolved)

    assert_equal [ pending_gate.id, stale.id ].sort, @task.gates.unresolved.pluck(:id).sort
  end

  # == ci_status ==

  test "ci_status reports pending, succeeded, failed and stale distinctly" do
    assert_equal "pending", create_gate.ci_status
    assert_equal "succeeded", create_gate(status: :resolved, resolution_data: { "conclusion" => "success" }).ci_status
    assert_equal "failed", create_gate(status: :resolved, resolution_data: { "conclusion" => "failure" }).ci_status
    assert_equal "stale", create_gate(status: :stale, diagnostic_reason: "no CI result").ci_status
  end

  test "a resolved gate with no conclusion at all reads as failed, never as a pass" do
    gate = create_gate(status: :resolved, resolution_data: {})

    assert_equal "failed", gate.ci_status
    assert_not gate.passed?
  end

  test "conclusion reads GitLab's status key as well as GitHub's conclusion key" do
    gate = create_gate(
      gate_type: :gitlab_pipeline_completed,
      metadata: { "repo_full_name" => "group/app", "pipeline_id" => 555 },
      status: :resolved,
      resolution_data: { "status" => "success" }
    )

    assert_equal "success", gate.conclusion
    assert_equal "succeeded", gate.ci_status
  end

  # == source metadata ==

  test "source names the provider, repository and the run identifier the gate waits on" do
    checks = create_gate
    workflow = create_gate(
      gate_type: :github_workflow_completed,
      metadata: { "repo_full_name" => "org/app", "run_id" => 99 }
    )
    pipeline = create_gate(
      gate_type: :gitlab_pipeline_completed,
      metadata: { "repo_full_name" => "group/app", "pipeline_id" => 555 }
    )

    assert_equal(
      { provider: "github", repo_full_name: "org/app", reference_type: "pr_number", reference: 42 },
      checks.source
    )
    assert_equal "run_id", workflow.source[:reference_type]
    assert_equal 99, workflow.source[:reference]
    assert_equal "gitlab", pipeline.source[:provider]
    assert_equal 555, pipeline.source[:reference]
  end

  # == reconciliation audit trail ==

  test "record_reconciliation! stamps the probe and prepends to the audit trail" do
    gate = create_gate

    gate.record_reconciliation!(outcome: "in_progress", detail: "1/2 check suites still running")
    gate.record_reconciliation!(outcome: "stale:ttl_expired", detail: "gave up")

    assert_equal 2, gate.reconcile_attempts
    assert_not_nil gate.last_reconciled_at
    assert_equal "stale:ttl_expired", gate.reconciliation_log.first["outcome"]
    assert_equal "in_progress", gate.reconciliation_log.second["outcome"]
    assert_equal "1/2 check suites still running", gate.reconciliation_log.second["detail"]
  end

  test "the audit trail keeps only the most recent entries" do
    gate = create_gate

    (Gate::RECONCILIATION_LOG_LIMIT + 5).times { |i| gate.record_reconciliation!(outcome: "probe-#{i}") }

    assert_equal Gate::RECONCILIATION_LOG_LIMIT, gate.reconciliation_log.size
    assert_equal "probe-#{Gate::RECONCILIATION_LOG_LIMIT + 4}", gate.reconciliation_log.first["outcome"]
  end

  private

  def create_gate(**attrs)
    @task.gates.create!({
      gate_type: :github_checks_completed,
      metadata: { "repo_full_name" => "org/app", "pr_number" => 42 },
      creator: @user
    }.merge(attrs))
  end
end
