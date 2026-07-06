# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-activities endpoint, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::ActivitiesPolicy
#          < Web::Company::Projects::Board::ActivitiesPolicy):
#   index (the only action) => project_accessible?  (read)
#
# This controller is read-only: it exposes a single GET #index and no writes, so
# every accessible role (owner/admin/collaborator/viewer) is permitted — the
# viewer is a collaborator and #index is a safe GET — while stranger/foreign
# admin are scoped out (Project.for_user(...).find raises RecordNotFound => 404
# before the policy runs). A project has no auto-created board and #index calls
# current_board (current_project.board || raise RecordNotFound), so a board is
# built here to keep allowed roles on the 200 path.
class Api::V1::Projects::Board::ActivitiesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_activities_path(@project) }
  end
end
