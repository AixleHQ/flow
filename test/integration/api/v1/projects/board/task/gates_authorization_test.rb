# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API task-gates endpoint, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::GatesPolicy):
#   destroy (write) => project_writable? (project_accessible? && !read_only?)
#
# `destroy` is the controller's only public action, so this is a single
# project-write matrix: owner / admin / collaborator are allowed (204 no_content,
# a 2xx success for the api transport), the read-only viewer is denied (403), and
# non-members (stranger / foreign admin) are scoped out — current_project resolves
# via Project.for_user(current_user).find(:project_id), which raises
# RecordNotFound (404) before the policy runs.
#
# A project has no auto-created board, so board/column/task are built here. There
# is no gate factory, so each allowed role destroys a throwaway pending Gate built
# inside the block (destroy mutates shared state). remove_gate performs a plain DB
# delete for this fixture — the column has no :auto column_workflow_binding, so
# record_pending_auto_trigger returns nil and no TriggerEngine/Temporal/vendor
# code runs.
class Api::V1::Projects::Board::Task::GatesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board  = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task   = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  # destroy mutates, so build a throwaway pending gate per role iteration.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      gate = Gate.create!(board_task: @task, creator: @owner, gate_type: "github_checks_completed")
      delete api_v1_project_task_gate_path(@project, @task, gate)
    end
  end
end
