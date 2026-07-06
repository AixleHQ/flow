# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Analytics controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::AnalyticsPolicy):
#   index? => project_accessible?   (read)
#
# The controller exposes a SINGLE action (index) and it is a READ. There is no
# write action, so no project_writable? gate applies: the read-only viewer
# collaborator is ALLOWED (accessible_by? is true for the owner, any collaborator
# incl. a viewer, and a same-company admin). Strangers and foreign-company admins
# fall outside Project.for_user, so the scoped `.find` raises RecordNotFound => 404.
# The heavy analytics services are wrapped in InertiaRails.defer, so the initial
# full-page GET renders without invoking them (no vendor/Temporal stubbing needed).
class Web::Company::Projects::AnalyticsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_analytics_path(@project) }
  end
end
