# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Settings controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::SettingsPolicy):
#   show?   => project_accessible?  (read)
#   update? => project_writable?    (write: project_accessible? && !read_only?)
#
# These are the controller's only public actions. Inaccessible project (stranger
# / foreign admin) => 404: current_project resolves through a per-user scoped
# `.find` that raises RecordNotFound before the policy for users outside the
# scope. The settings page reads only the project + its members, so no extra
# prerequisite fixtures are needed; the update body permits :name, so a plain
# rename is a clean, idempotent valid write for every allowed role.
class Web::Company::Projects::SettingsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup { setup_project_authz_personas }

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read { get company_project_settings_path(@project) }
  end

  test "update is a project write" do
    assert_project_write do
      patch company_project_settings_path(@project), params: { project: { name: "Renamed" } }
    end
  end
end
