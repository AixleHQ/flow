# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Web::Company::Projects::BoardsController,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::BoardsPolicy < Web::Company::ApplicationPolicy):
#   show?                        => project_accessible?                        (read)
#   create? / update? / destroy? => project_admin? (project_writable? && admin) (write)
#
# The controller exposes exactly ONE routed action (confirmed via
# `rails routes -c Web::Company::Projects::BoardsController`):
#   GET /company/projects/:project_id/board -> boards#show
# create?/update?/destroy? have NO routes on this controller, so they are not
# reachable at the request layer and are not tested here.
#
# show is a plain project read: current_project resolves via
# Project.for_user(current_user).find(params[:project_id]) in the base controller
# BEFORE the policy runs, so owner / company admin / employee-collaborator /
# viewer-collaborator all reach a 200 page, while same-company strangers and
# foreign-company admins are scoped out to 404 by the `.find` (RecordNotFound) —
# there is no 302+alert denial branch for reads here. No board fixture is needed:
# show renders the same Inertia page (200) whether or not the project has a board.
class Web::Company::Projects::BoardsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read { get company_project_board_path(@project) }
  end
end
