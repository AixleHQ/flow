# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::BoardsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "show renders the board page with a populated board" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    create(:board_task, board: board, board_column: column)

    get company_project_board_path(@project)
    assert_response :success
    assert_inertia_page "Projects/Board/BoardPage"
  end

  test "show ships one page of tasks per column, not the whole board" do
    board = create(:board, project: @project)
    backlog = create(:board_column, board: board, name: "Backlog")
    done = create(:board_column, board: board, name: "Done")
    overflow = BoardTask::PAGE_SIZE + 3
    overflow.times { |i| create(:board_task, board: board, board_column: backlog, position: i) }
    create(:board_task, board: board, board_column: done, position: 0)

    get company_project_board_path(@project)
    assert_response :success

    props = inertia.props
    assert_equal BoardTask::PAGE_SIZE, props[:tasks].count { |t| t[:boardColumnId] == backlog.id }
    assert_equal 1, props[:tasks].count { |t| t[:boardColumnId] == done.id }
    assert_equal BoardTask::PAGE_SIZE, props[:tasksPageSize]
  end

  test "show sends every column its total task count, excluding archived tasks" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    create_list(:board_task, 2, board: board, board_column: column)
    create(:board_task, board: board, board_column: column, archived_at: Time.current)

    get company_project_board_path(@project)
    assert_response :success

    column_props = inertia.props[:columns].find { |c| c[:id] == column.id }
    assert_equal 2, column_props[:tasksCount]
  end

  test "show sends the board-wide tag and epic options the filters need" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    create(:board_task, board: board, board_column: column, tags: %w[api ui])
    epic = create(:board_task, board: board, board_column: column, task_type: :epic, title: "Checkout revamp")

    get company_project_board_path(@project)
    assert_response :success

    props = inertia.props
    assert_equal %w[api ui], props[:boardTags]
    assert_equal [ { "id" => epic.id, "title" => "Checkout revamp" } ], props[:epics]
  end

  test "show renders the board page with a selected task" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)

    get company_project_board_path(@project, task: task.id)
    assert_response :success
    assert_inertia_page "Projects/Board/BoardPage"
  end
end
