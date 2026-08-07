# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::BoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "show renders empty board page when no board" do
    get company_project_board_path(@project)
    assert_inertia_page "Projects/Board/BoardPage"
  end

  test "show renders board page with board" do
    board = create(:board, project: @project)
    create(:board_column, board: board)

    get company_project_board_path(@project)
    assert_inertia_page "Projects/Board/BoardPage"
  end

  test "show renders board page with selected task" do
    board = create(:board, project: @project)
    col = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: col)

    Bullet.enable = false
    get company_project_board_path(@project, task: task.id)
    assert_inertia_page "Projects/Board/BoardPage"
  ensure
    Bullet.enable = true
  end

  test "show excludes archived tasks from the default board load" do
    board = create(:board, project: @project)
    col = create(:board_column, board: board)
    active = create(:board_task, board: board, board_column: col)
    archived = create(:board_task, board: board, board_column: col, archived_at: Time.current)

    get company_project_board_path(@project)
    assert_inertia_page "Projects/Board/BoardPage"

    assert_inertia_props do |props|
      ids = props[:tasks].map { |t| t[:id] }
      ids.include?(active.id) && ids.exclude?(archived.id)
    end
  end

  test "show names the selected task's parent epic even when the epic is archived" do
    board = create(:board, project: @project)
    col = create(:board_column, board: board)
    epic = create(:board_task, board: board, board_column: col, task_type: :epic,
      title: "Checkout revamp", archived_at: Time.current)
    task = create(:board_task, board: board, board_column: col, parent_task: epic)

    Bullet.enable = false
    get company_project_board_path(@project, task: task.id)
    assert_inertia_page "Projects/Board/BoardPage"

    # The archived epic is absent from the board's task list, so the detail payload has to
    # carry its title — otherwise the task view cannot show which epic the task belongs to.
    assert_inertia_props do |props|
      props[:tasks].map { |t| t[:id] }.exclude?(epic.id) &&
        props[:selectedTask][:parentTaskId] == epic.id &&
        props[:selectedTask][:parentTaskTitle] == "Checkout revamp"
    end
  ensure
    Bullet.enable = true
  end

  test "show includes assets_count for each task without N+1 queries" do
    board = create(:board, project: @project)
    col = create(:board_column, board: board)
    task1 = create(:board_task, board: board, board_column: col)
    task2 = create(:board_task, board: board, board_column: col)
    create(:task_asset, board_task: task1, author: @user)
    create(:task_asset, board_task: task1, author: @user)
    create(:task_asset, board_task: task2, author: @user)

    get company_project_board_path(@project)
    assert_inertia_page "Projects/Board/BoardPage"

    assert_inertia_props do |props|
      task1_data = props[:tasks].find { |t| t[:id] == task1.id }
      task2_data = props[:tasks].find { |t| t[:id] == task2.id }
      task1_data[:assetsCount] == 2 && task2_data[:assetsCount] == 1
    end
  end
end
