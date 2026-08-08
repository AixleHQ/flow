# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Sessions controller,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::SessionsPolicy):
#   index? / show? => project_accessible?  (read)
#   new?           => project_writable?    (write-gated GET — allowed roles get a
#                                           200 page, the viewer is denied, and
#                                           non-members are scoped out to 404)
class Web::Company::Projects::SessionsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    # The owner shares both phases so this file keeps measuring the POLICY. Who
    # may open someone else's session is a separate, owner-controlled gate
    # (TerminalSession#visible_to?, covered in sessions_visibility_test.rb).
    @owner.update!(share_active_sessions: true, share_completed_sessions: true)
    @session = create(:terminal_session, :agent_session, project: @project, user: @owner)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_sessions_path(@project) }
  end

  test "show is a project read" do
    assert_project_read { get company_project_session_path(@project, @session) }
  end

  test "new is write-gated (GET): allowed roles 200, viewer denied, non-members 404" do
    assert_project_write(allowed: :success) { get new_company_project_session_path(@project) }
  end
end
