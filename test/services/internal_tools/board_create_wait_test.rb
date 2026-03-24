# frozen_string_literal: true

require "test_helper"

class InternalTools::BoardCreateWaitTest < ActiveSupport::TestCase
  setup do
    @company     = create(:company)
    @user        = create(:user, company: @company)
    @integration = create(:integration, :github, :active, company: @company, connected_by: @user)
    @project     = create(:project, company: @company, owner: @user)
    @board       = create(:board, project: @project)
    @column      = create(:board_column, board: @board, name: "In Progress", position: 1)
    @task        = create(:board_task, board: @board, board_column: @column, title: "My task")

    # Repository linked to the project — required for repo validation in board_create_wait
    @repo_name   = "org/app"
    create(:repository, full_name: @repo_name, scope: @project, integration: @integration)

    workflow      = create(:workflow, scope: @company)
    step          = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    @step_run     = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  # == github_checks_completed ==

  test "creates a github_checks_completed wait with valid params" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_checks_completed",
        repo_full_name: @repo_name,
        pr_number:      42
      },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @task.id, data["task_id"]
    assert_equal "github_checks_completed", data["wait_type"]
    assert_equal "pending", data["status"]
    assert_equal @repo_name, data["metadata"]["repo_full_name"]
    assert_equal 42, data["metadata"]["pr_number"]
  end

  test "creates a persisted TaskWait record" do
    assert_difference -> { TaskWait.count }, 1 do
      InternalTools::BoardCreateWait.new(
        params: {
          task_id:        @task.id,
          wait_type:      "github_checks_completed",
          repo_full_name: @repo_name,
          pr_number:      7
        },
        session: @session
      ).execute
    end
  end

  test "sets creator from workflow run user" do
    InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_checks_completed",
        repo_full_name: @repo_name,
        pr_number:      42
      },
      session: @session
    ).execute

    wait = TaskWait.last
    assert_equal @user, wait.creator
  end

  # == validation errors ==

  test "returns error for unknown wait_type" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:       @task.id,
        wait_type:     "unknown_type",
        repo_full_name: "org/app",
        pr_number:     1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Unsupported wait_type"
  end

  test "returns error when task not found" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:       999_999,
        wait_type:     "github_checks_completed",
        repo_full_name: "org/app",
        pr_number:     1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Task not found"
  end

  test "returns error when repo_full_name is missing" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:   @task.id,
        wait_type: "github_checks_completed",
        pr_number: 1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "repo_full_name is required"
  end

  test "returns error when pr_number is missing" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_checks_completed",
        repo_full_name: "org/app"
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "pr_number must be a positive integer"
  end

  test "returns error when pr_number is zero" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_checks_completed",
        repo_full_name: @repo_name,
        pr_number:      0
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "pr_number must be a positive integer"
  end

  test "returns error when repository is not linked to the project" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_checks_completed",
        repo_full_name: "other/unlinked-repo",
        pr_number:      1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not linked to this task's project"
  end

  # == github_workflow_completed ==

  test "creates a github_workflow_completed wait with valid params" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_workflow_completed",
        repo_full_name: @repo_name,
        run_id:         5000
      },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    data = JSON.parse(result[:stdout])
    assert_equal @task.id, data["task_id"]
    assert_equal "github_workflow_completed", data["wait_type"]
    assert_equal "pending", data["status"]
    assert_equal @repo_name, data["metadata"]["repo_full_name"]
    assert_equal 5000, data["metadata"]["run_id"]
  end

  test "creates a persisted TaskWait record for github_workflow_completed" do
    assert_difference -> { TaskWait.count }, 1 do
      InternalTools::BoardCreateWait.new(
        params: {
          task_id:        @task.id,
          wait_type:      "github_workflow_completed",
          repo_full_name: @repo_name,
          run_id:         7
        },
        session: @session
      ).execute
    end
  end

  test "returns error when run_id is missing for github_workflow_completed" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_workflow_completed",
        repo_full_name: @repo_name
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "run_id must be a positive integer"
  end

  test "returns error when run_id is zero for github_workflow_completed" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_workflow_completed",
        repo_full_name: @repo_name,
        run_id:         0
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "run_id must be a positive integer"
  end

  test "returns error when repo_full_name is missing for github_workflow_completed" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:   @task.id,
        wait_type: "github_workflow_completed",
        run_id:    1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "repo_full_name is required"
  end

  test "returns error when repository is not linked to the project for github_workflow_completed" do
    result = InternalTools::BoardCreateWait.new(
      params: {
        task_id:        @task.id,
        wait_type:      "github_workflow_completed",
        repo_full_name: "other/unlinked-repo",
        run_id:         1
      },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not linked to this task's project"
  end
end
