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

  test "resolves a pending gate matching repo and PR number" do
    gate = @task.gates.create!(
      gate_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_gate).with(
      gate: gate,
      resolution_data: { conclusion: "success" }
    ).once

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

    TaskService.expects(:resolve_gate).never

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

    TaskService.expects(:resolve_gate).never

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

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "resolves multiple matching gates across different tasks" do
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
    TaskService.stubs(:resolve_gate).with do |args|
      resolved_gates << args[:gate]
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

    TaskService.expects(:resolve_gate).never

    GateService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
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
