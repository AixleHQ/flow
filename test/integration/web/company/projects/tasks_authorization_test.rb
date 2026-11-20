# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::TasksController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::TasksPolicy): show? => project_accessible? (read).
# The one routed action is GET /company/projects/:project_id/tasks/:number. As on the
# board, current_project resolves through Project.for_user before the policy runs,
# so strangers and foreign-company admins are scoped out to 404.
class Web::Company::Projects::TasksAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    board = create(:board, project: @project)
    @task = create(:board_task, board: board, board_column: create(:board_column, board: board))
  end

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read { get company_project_task_path(@project, @task.number) }
  end
end
