# frozen_string_literal: true

require "test_helper"

class WaitServiceTest < ActiveSupport::TestCase
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

  test "resolves a pending wait matching repo and PR number" do
    wait = @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).with(
      wait: wait,
      resolution_data: { conclusion: "success" }
    ).once

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "does nothing when no waits match the repo" do
    @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: "other/repo", pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "does nothing when no waits match the PR number" do
    @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 99 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "failure"
    )
  end

  test "does nothing when no pending waits exist" do
    @task.task_waits.create!(
      wait_type: :github_checks_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  test "resolves multiple matching waits across different tasks" do
    task2 = create(:board_task, board: @board, board_column: @column, assignee: @user)

    wait1 = @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )
    wait2 = task2.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    resolved_waits = []
    TaskService.stubs(:resolve_wait).with do |args|
      resolved_waits << args[:wait]
      true
    end

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )

    assert_includes resolved_waits, wait1
    assert_includes resolved_waits, wait2
  end

  test "does not resolve waits for tasks in a different project" do
    other_project = create(:project, company: @company, owner: @user)
    other_board   = create(:board, project: other_project)
    other_column  = create(:board_column, board: other_board)
    other_task    = create(:board_task, board: other_board, board_column: other_column)

    # This wait belongs to a project with no connection to @repo_name
    other_task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_checks(
      repo_full_name: @repo_name,
      pr_number: 42,
      conclusion: "success"
    )
  end

  # == resolve_github_workflow ==

  test "resolves a pending workflow wait matching repo and run_id" do
    wait = @task.task_waits.create!(
      wait_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).with(
      wait: wait,
      resolution_data: { conclusion: "success" }
    ).once

    WaitService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no workflow waits match the repo" do
    @task.task_waits.create!(
      wait_type: :github_workflow_completed,
      metadata:  { repo_full_name: "other/repo", run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no workflow waits match the run_id" do
    @task.task_waits.create!(
      wait_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 9999 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does nothing when no pending workflow waits exist" do
    @task.task_waits.create!(
      wait_type: :github_workflow_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, run_id: 1001 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 1001,
      conclusion: "success"
    )
  end

  test "does not match github_checks_completed waits when resolving workflow" do
    @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata:  { repo_full_name: @repo_name, pr_number: 42 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_github_workflow(
      repo_full_name: @repo_name,
      run_id: 42,
      conclusion: "success"
    )
  end

  # == resolve_gitlab_pipeline ==

  test "resolves a pending gitlab pipeline wait matching repo and pipeline_id" do
    wait = @task.task_waits.create!(
      wait_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).with(
      wait: wait,
      resolution_data: { status: "success" }
    ).once

    WaitService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does nothing when no gitlab pipeline waits match the repo" do
    @task.task_waits.create!(
      wait_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: "other/repo", pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does nothing when no gitlab pipeline waits match the pipeline_id" do
    @task.task_waits.create!(
      wait_type: :gitlab_pipeline_completed,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 9999 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "failed"
    )
  end

  test "does nothing when gitlab pipeline wait is already resolved" do
    @task.task_waits.create!(
      wait_type: :gitlab_pipeline_completed,
      status:    :resolved,
      metadata:  { repo_full_name: @repo_name, pipeline_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end

  test "does not match github waits when resolving gitlab pipeline" do
    @task.task_waits.create!(
      wait_type: :github_workflow_completed,
      metadata:  { repo_full_name: @repo_name, run_id: 5000 },
      creator: @user
    )

    TaskService.expects(:resolve_wait).never

    WaitService.resolve_gitlab_pipeline(
      repo_full_name: @repo_name,
      pipeline_id: 5000,
      status: "success"
    )
  end
end
