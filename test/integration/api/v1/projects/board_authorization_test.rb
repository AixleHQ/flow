# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board endpoint
# (Api::V1::Projects::BoardController), via the shared AuthorizationMatrix
# harness (docs/testing.md §2).
#
# Routes (all on the singular /api/v1/projects/:project_id/board):
#   POST => create, PATCH/PUT => update, DELETE => destroy.
# There are NO read (index/show) actions here — every action is a WRITE.
# (view_presets/columns/tasks live on sibling controllers.)
#
# Policy (Api::V1::Projects::BoardPolicy):
#   create? / update? / destroy? => project_writable?
# The API policy OVERRIDES its web base (Web::Company::Projects::BoardsPolicy),
# which gates writes on project_admin? (owner-only); the API relaxes them to
# project_writable?, so the company admin (non-owner) and the employee
# collaborator are permitted — exactly the harness's project-write preset:
# owner/admin/collaborator allowed, viewer denied (403), stranger/foreign 404
# (Project.for_user(...).find raises RecordNotFound before the policy).
# (create_from_preset? is defined on the policy but is not a routed action.)
#
# The board is a per-project singleton (validates :project_id, uniqueness: true),
# built in setup so update/destroy have a target.
class Api::V1::Projects::BoardAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
  end

  teardown { teardown_authz }

  # The board already exists (setup), so the allowed roles pass authorization and
  # reach the action's idempotency guard, which returns 422 — evidence authz
  # passed (a denial would be 403), while the viewer is 403 and non-members 404.
  test "create is a project write (allowed roles hit the board-exists 422 guard)" do
    assert_project_write(transport: :api, allowed: :unprocessable_entity) do
      post api_v1_project_board_path(@project), params: { board: { name: "New Board" } }, as: :json
    end
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_board_path(@project), params: { board: { name: "Renamed" } }, as: :json
    end
  end

  # destroy removes the singleton board, so re-create it before each allowed
  # role's request (each allowed role deletes its own board => 204 no_content).
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      create(:board, project: @project) unless Board.exists?(project: @project)
      delete api_v1_project_board_path(@project)
    end
  end
end
