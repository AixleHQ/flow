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
end
