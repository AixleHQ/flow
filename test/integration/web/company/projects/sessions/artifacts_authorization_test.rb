# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped session Artifacts
# controller (review of a terminal session's output assets), via the shared
# AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::Sessions::ArtifactsPolicy):
#   index?  => project_accessible?  (read  — owner/admin/collaborator/viewer)
#   review? => project_writable?    (write — viewer denied as read_only)
# Inaccessible project (stranger / foreign admin) => 404: current_project is
# loaded via Project.for_user(current_user).find(params[:project_id]), whose
# scope excludes them, so `.find` raises RecordNotFound before the policy runs.
#
# Allowed-write body: review does params.require(:decisions) then permits only
# real output-asset ids. The fixture session has no output assets, so a minimal
# non-blank decisions hash with an unknown key satisfies require, is stripped to
# a no-op by permit, and the action just flips artifacts_reviewed and redirects
# to the session (302, notice not alert) — no Temporal/SessionService is touched.
class Web::Company::Projects::Sessions::ArtifactsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    # The owner shares both phases so this file keeps measuring the POLICY. Who
    # may open someone else's session is a separate, owner-controlled gate
    # (TerminalSession#visible_to?, covered in sessions_visibility_test.rb);
    # leaving it at the default would deny every non-owner persona here for a
    # reason that has nothing to do with project roles.
    @owner.update!(share_active_sessions: true, share_completed_sessions: true)
    @session = create(:terminal_session, :agent_session, project: @project, user: @owner)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read { get company_project_session_artifacts_path(@project, @session) }
  end

  test "review is a project write" do
    assert_project_write do
      post review_company_project_session_artifacts_path(@project, @session),
           params: { decisions: { "noop" => "dismiss" } }
    end
  end
end
