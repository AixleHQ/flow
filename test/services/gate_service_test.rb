# frozen_string_literal: true

require "test_helper"

class GateServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user    = create(:user, company: @company)
    @integration = create(:integration, :github, :active, company: @company, connected_by: @user)

    @project = create(:project, company: @company, owner: @user)
    @board   = create(:board, project: @project)
    @column  = create(:board_column, board: @board)
    @task    = create(:board_task, board: @board, board_column: @column, assignee: @user)

    # Repository linked to the project
    @repo_name = "org/app"
    @repository = create(:repository, full_name: @repo_name, scope: @project, integration: @integration)
  end

  # == resolve_github_checks ==

  test "a completed suite has a matching pending gate checked against GitHub" do
    gate = @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    GateReconciler.expects(:reconcile).with(gate).once

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "does nothing when no gates match the repo" do
    @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: "other/repo", pr_number: 42 },
      creator: @user
    )

    GateReconciler.expects(:reconcile).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "does nothing when no gates match the PR number" do
    @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 99 },
      creator: @user
    )

    GateReconciler.expects(:reconcile).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "failure"
    )
  end

  test "does nothing when no pending gates exist" do
    @task.gates.create!(
      gate_type: :github_checks_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    GateReconciler.expects(:reconcile).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "checks every matching gate across different tasks" do
    task2 = create(:board_task, board: @board, board_column: @column, assignee: @user)

    gate1 = @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )
    gate2 = task2.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    resolved_gates = []
    GateReconciler.stubs(:reconcile).with do |gate|
      resolved_gates << gate
      true
    end

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )

    assert_includes resolved_gates, gate1
    assert_includes resolved_gates, gate2
  end

  test "does not resolve gates for tasks in a different project" do
    other_project = create(:project, company: @company, owner: @user)
    other_board   = create(:board, project: other_project)
    other_column  = create(:board_column, board: other_board)
    other_task    = create(:board_task, board: other_board, board_column: other_column)

    # This gate belongs to a project with no connection to @repo_name
    other_task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    GateReconciler.expects(:reconcile).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  # The event's own verdict is one suite's; the gate resolves on every suite of
  # the pull request's current head, as GitHub reports it now.
  test "a quick suite finishing green does not pass a gate whose other suites failed" do
    gate = @task.gates.create!(gate_type: :github_checks_completed,
                               metadata: { repo_full_name: @repo_name, pr_number: 42 }, creator: @user)
    probe = mock("probe")
    probe.stubs(:call).returns(Ci::ProbeResult.completed("failure", "2 check suite(s) completed on PR #42"))
    Ci::GateProbe.stubs(:new).returns(probe)

    GateService.resolve_github_checks(repo_full_name: @repo_name, pr_number: 42, conclusion: "success")

    assert_equal "failure", gate.reload.resolution_data["conclusion"]
  end

  test "a suite finishing while others still run leaves the gate pending" do
    gate = @task.gates.create!(gate_type: :github_checks_completed,
                               metadata: { repo_full_name: @repo_name, pr_number: 42 }, creator: @user)
    probe = mock("probe")
    probe.stubs(:call).returns(Ci::ProbeResult.in_progress("1/2 check suites still running on PR #42"))
    Ci::GateProbe.stubs(:new).returns(probe)

    GateService.resolve_github_checks(repo_full_name: @repo_name, pr_number: 42, conclusion: "success")

    assert_predicate gate.reload, :pending?
  end

  # == resolve_github_workflow ==

  test "resolves a pending workflow gate matching repo and run_id" do
    gate = @task.gates.create!(
      gate_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).with(
      gate: gate,
      resolution_data: { conclusion: "success" }
    ).once

    GateService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no workflow gates match the repo" do
    @task.gates.create!(
      gate_type: :github_workflow_completed,
      metadata:  { repo_full_name: "other/repo", run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no workflow gates match the run_id" do
    @task.gates.create!(
      gate_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 9999 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no pending workflow gates exist" do
    @task.gates.create!(
      gate_type: :github_workflow_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does not match github_checks_completed gates when resolving workflow" do
    @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 42,
      conclusion: "success"
    )
  end

  # == resolve_gitlab_pipeline ==

  test "a delivery resolves only the gates of the repository it authenticated as" do
    gitlab = create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    ours = create(:repository, full_name: "group/app", scope: @project, integration: gitlab)
    other_company = create(:company)
    other_user = create(:user, company: other_company)
    other_project = create(:project, company: other_company, owner: other_user)
    create(:repository, full_name: "group/app", scope: other_project,
                        integration: create(:integration, :gitlab, :active, company: other_company, connected_by: other_user))
    other_board = create(:board, project: other_project)
    other_task = create(:board_task, board: other_board, board_column: create(:board_column, board: other_board))
    mine = @task.gates.create!(gate_type: :gitlab_pipeline_completed, creator: @user,
                               metadata: { repo_full_name: "group/app", pipeline_id: 77 })
    theirs = other_task.gates.create!(gate_type: :gitlab_pipeline_completed, creator: other_user,
                                      metadata: { repo_full_name: "group/app", pipeline_id: 77 })
    resolved = []
    TaskService.stubs(:resolve_gate).with { |args| resolved << args[:gate] }

    GateService.resolve_gitlab_pipeline(repository: ours, repo_full_name: "group/app", pipeline_id: 77, status: "success")

    assert_equal [ mine ], resolved
    assert_not_includes resolved, theirs
  end


  test "resolves a pending gitlab pipeline gate matching repo and pipeline_id" do
    gate = @task.gates.create!(
      gate_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).with(
      gate: gate,
      resolution_data: { status: "success" }
    ).once

    GateService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does nothing when no gitlab pipeline gates match the repo" do
    @task.gates.create!(
      gate_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: "other/repo", pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does nothing when no gitlab pipeline gates match the pipeline_id" do
    @task.gates.create!(
      gate_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 9999 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "failed"
    )
  end

  test "does nothing when gitlab pipeline gate is already resolved" do
    @task.gates.create!(
      gate_type: :gitlab_pipeline_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does not match github gates when resolving gitlab pipeline" do
    @task.gates.create!(
      gate_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).never

    GateService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end
end
