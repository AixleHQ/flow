# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Statistic::RecentActivityControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)
  end

  # ====== SHOW Tests ======

  test "#show returns 200 for company admin" do
    sign_in @admin

    get :show

    assert_response :success
  end

  test "#show returns 200 for company employee" do
    sign_in @employee

    get :show

    assert_response :success
  end

  test "#show requires authentication" do
    get :show

    assert_response :unauthorized
  end

  test "#show returns activities array and meta object" do
    sign_in @admin

    get :show

    assert_response :success
    json = response.parsed_body
    assert { json.key?("activities") }
    assert { json["activities"].is_a?(Array) }
    assert { json.key?("meta") }
    assert { json["meta"].key?("total") }
    assert { json["meta"].key?("page") }
    assert { json["meta"].key?("per_page") }
  end

  test "#show activity items include required fields" do
    board = create(:board, project: create(:project, company: @company, owner: @admin))
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)
    BoardActivity.create!(board: board, board_task: task, actor: @admin, event_type: "task_created", metadata: {})

    sign_in @admin

    get :show

    assert_response :success
    activities = response.parsed_body["activities"]
    assert { activities.any? }
    entry = activities.first
    assert { entry.key?("event_type") }
    assert { entry.key?("description") }
    assert { entry.key?("actor_name") }
    assert { entry.key?("actor_type") }
    assert { entry.key?("occurred_at") }
  end

  test "#show respects page and per_page params" do
    sign_in @admin

    get :show, params: { page: 2, per_page: 5 }

    assert_response :success
    json = response.parsed_body
    assert { json["meta"]["page"] == 2 }
    assert { json["meta"]["per_page"] == 5 }
  end

  test "#show excludes activity from other companies" do
    other_project = create(:project, company: @other_company, owner: @other_admin)
    other_board = create(:board, project: other_project)
    other_column = create(:board_column, board: other_board)
    other_task = create(:board_task, board: other_board, board_column: other_column)
    BoardActivity.create!(board: other_board, board_task: other_task, actor: @other_admin, event_type: "task_created", metadata: {})

    sign_in @admin

    get :show

    assert_response :success
    activities = response.parsed_body["activities"]
    assert { activities.none? { |a| a["actor_name"] == @other_admin.name } }
  end
end
