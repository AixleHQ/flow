# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Overview controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::OverviewPolicy):
#   index? => project_accessible?  (read)
#
# The controller exposes a single READ action (GET .../overview). Allowed roles
# (owner/admin/collaborator/viewer) render 200; the read-only viewer is permitted
# because a GET never hits the project_writable? backstop. Stranger and
# foreign-company admin are scoped out by Project.for_user (RecordNotFound => 404
# before the policy runs).
class Web::Company::Projects::OverviewAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_overview_index_path(@project) }
  end
end
