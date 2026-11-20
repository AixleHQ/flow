# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::TasksRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board, name: "Backlog")
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "show renders the task page for the task with that board number" do
    other = create(:board_task, board: @board, board_column: @column, title: "Not this one")
    task = create(:board_task, board: @board, board_column: @column, title: "Ship the task page", tags: %w[ui])
    create(:task_comment, board_task: task, author: @user, body: "Looks good")
    assert_not_equal other.number, task.number

    get company_project_task_path(@project, task.number)

    assert_response :success
    assert_inertia_page "Projects/Board/TaskPage"
    props = inertia.props
    assert_equal task.id, props[:selectedTask][:id]
    assert_equal "Ship the task page", props[:selectedTask][:title]
    assert_equal [ "Looks good" ], props[:taskComments].pluck(:body)
    assert_equal [ "Backlog" ], props[:columns].pluck(:name)
    assert_equal %w[ui], props[:boardTags]
    assert_equal @user.id, props[:currentUserId]
  end

  test "show opens an archived task" do
    task = create(:board_task, board: @board, board_column: @column, archived_at: Time.current)

    get company_project_task_path(@project, task.number)

    assert_response :success
    assert_equal task.id, inertia.props[:selectedTask][:id]
  end

  test "a number no task on the board has is not found" do
    get company_project_task_path(@project, 999)

    assert_response :not_found
  end

  test "a project without a board has no task pages" do
    project = create(:project, company: @company, owner: @user)

    get company_project_task_path(project, 1)

    assert_response :not_found
  end
end
