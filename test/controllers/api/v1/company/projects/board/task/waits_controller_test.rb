# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::WaitsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    @column = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Test Task", board: @board, board_column: @column)
  end

  test "#destroy removes pending wait for project member" do
    wait = @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 12 },
      creator: @owner
    )
    sign_in @collaborator

    assert_difference("TaskWait.count", -1) do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: wait.id }
    end

    assert_response :no_content
  end

  test "#destroy does not remove resolved wait" do
    wait = @task.task_waits.create!(
      wait_type: :github_checks_completed,
      status: :resolved,
      resolved_at: Time.current,
      metadata: { repo_full_name: "org/app", pr_number: 12 },
      creator: @owner
    )
    sign_in @owner

    assert_no_difference("TaskWait.count") do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: wait.id }
    end

    assert_response :not_found
  end

  test "#destroy not accessible by non-member" do
    wait = @task.task_waits.create!(
      wait_type: :github_checks_completed,
      metadata: { repo_full_name: "org/app", pr_number: 12 },
      creator: @owner
    )
    sign_in @other_user

    assert_no_difference("TaskWait.count") do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: wait.id }
    end

    assert_response :forbidden
  end
end
