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

  test "show renders the board page with a selected task" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)

    get company_project_board_path(@project, task: task.id)
    assert_response :success
    assert_inertia_page "Projects/Board/BoardPage"
  end
end
