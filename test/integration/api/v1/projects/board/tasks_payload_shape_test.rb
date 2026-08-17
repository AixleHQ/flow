# frozen_string_literal: true

require "test_helper"

# The board renders one card from two payloads: the Inertia props of the board page,
# and the JSON this endpoint returns whenever a column is re-queried server-side (a
# filter, a tag clicked on a card, a scrolled column). They have to agree key for key.
#
# They did not: Alba camelizes only the attribute names it declares, so a hash built
# inside an `attribute` block reached the props camelized (the Inertia transformer
# walks the whole tree) and the JSON endpoint snake_case. A gate arrived as `gateType`
# on load and `gate_type` after a filter, and the board — reading `gate.gateType` —
# crashed on the second shape.
class Api::V1::Projects::Board::TasksPayloadShapeTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column, tags: %w[frontend])
    Gate.create!(board_task: @task, creator: @user, gate_type: "github_checks_completed",
      metadata: { repo_full_name: "AixleHQ/flow", pr_number: 42 })
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "a tag-filtered task carries its gates under the keys the frontend reads" do
    get api_v1_project_tasks_path(@project), params: { tags: [ "frontend" ], tags_match: "all" }, as: :json

    assert_response :success
    gate = JSON.parse(response.body).sole["pendingGates"].sole
    assert_equal "github_checks_completed", gate["gateType"]
    assert_equal "pending", gate["ciStatus"]
    assert_not gate.key?("gate_type"), "nested keys must reach the frontend camelized, like the props do"
    assert_equal 42, gate.dig("metadata", "prNumber")
  end

  test "the JSON payload and the board props describe the same task identically" do
    # `age_seconds` is derived from the clock, so both reads have to happen at one instant.
    freeze_time do
      get api_v1_project_tasks_path(@project), params: { board_column_id: @column.id }, as: :json
      assert_response :success
      from_api = JSON.parse(response.body).sole

      get company_project_board_path(@project)
      assert_response :success
      from_props = inertia.props[:tasks].sole.deep_stringify_keys

      assert_equal from_props, from_api
    end
  end

  test "the agent-facing payload keeps the Ruby spelling" do
    # MCP and workflow tools read snake_case everywhere else; camelizing for the web
    # client must not reach them.
    gate = BoardTaskResource.new(@task.reload, params: { snake_keys: true }).to_h["pending_gates"].sole

    assert_equal "github_checks_completed", gate[:gate_type]
    assert_equal "AixleHQ/flow", gate[:metadata]["repo_full_name"]
  end
end
