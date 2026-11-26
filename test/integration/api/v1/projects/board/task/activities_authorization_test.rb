# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-task activities endpoint,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::ActivitiesPolicy < web policy):
#   index? / show? => project_accessible?  (read)
#
# Both actions are plain project reads: owner/admin/collaborator/viewer are permitted;
# stranger/foreign admin are scoped out to 404 (Project.for_user(...).find raises
# RecordNotFound before the policy).
# There are no writes, so the viewer (read-only) is permitted on this GET. A project
# has no auto-created board, so the board/column/task fixtures are built here.
class Api::V1::Projects::Board::Task::ActivitiesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
    @activity = BoardActivity.create!(
      board: @board, board_task: @task, actor: @owner, actor_type: :human, event_type: :task_updated,
      metadata: { "changes" => { "title" => [ "Draft", "Ship it" ], "priority" => [ nil, "high" ] } }
    )
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_activities_path(@project, @task) }
  end

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_activity_path(@project, @task, @activity) }
  end

  test "show returns the recorded changes, named for people" do
    sign_in_as(@collaborator)

    get api_v1_project_task_activity_path(@project, @task, @activity)

    assert_response :success
    assert_equal [ { "field" => "title", "label" => "Title", "before" => "Draft", "after" => "Ship it" },
                   { "field" => "priority", "label" => "Priority", "before" => nil, "after" => "High" } ],
                 response.parsed_body["changes"]
  end

  test "show does not reach an activity of another task" do
    other = create(:board_task, board: @board, board_column: @column)
    sign_in_as(@collaborator)

    get api_v1_project_task_activity_path(@project, other, @activity)

    assert_response :not_found
  end
end
