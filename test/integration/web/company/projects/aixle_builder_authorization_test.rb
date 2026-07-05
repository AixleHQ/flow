# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Aixle Builder
# controller, via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::AixleBuilderPolicy):
#   show? / show_session? => project_accessible?  (read)
#   start? / finish?      => project_writable?     (write: accessible AND not
#                                                   read_only, so the viewer is denied)
# Inaccessible project (stranger / foreign admin) => 404: current_project is
# loaded via Project.for_user(current_user).find(...) in a before_action, which
# raises RecordNotFound (rescued to 404 by show_exceptions=:rescuable) before the
# policy runs — an inaccessible project is indistinguishable from a missing one.
#
# Body-scoping notes (Temporal/vendors are NOT stubbed):
# * show_session / finish scope the session by `user: current_user`, so each
#   reading/finishing member needs their OWN aixle_builder session to reach the
#   action body (else the body returns head :not_found). Sessions are keyed by
#   role and selected inside the block; strangers/foreigners 404 on the project
#   before the id is used, so they fall back to any valid session.
# * start has no param guard: an empty body would reach Temporal. Sending an
#   invalid preferred_model fails the requested_model format validation, so the
#   session never persists (create_and_start returns before start_temporal_workflow)
#   and the controller redirects back to the builder with a *validation* alert (a
#   302 that is NOT the authorization denial) without touching Temporal — hence
#   `allowed: :redirect` (the allowed path carries a non-nil alert, so the default
#   allowed-write assert_nil flash[:alert] can't apply).
# * finish on an own :started session with a nil temporal_workflow_id transitions
#   state purely in the DB (no Temporal signal) and redirects to the session page
#   with no alert — the default allowed-write contract.
class Web::Company::Projects::AixleBuilderAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    # show_session / finish scope by `user: current_user`, so each member reads
    # or finishes its own session; strangers/foreigners 404 before the lookup.
    @sessions = {
      owner: create(:terminal_session, :aixle_builder, :started, project: @project, user: @owner),
      admin: create(:terminal_session, :aixle_builder, :started, project: @project, user: @admin),
      collaborator: create(:terminal_session, :aixle_builder, :started, project: @project, user: @collaborator),
      viewer: create(:terminal_session, :aixle_builder, :started, project: @project, user: @viewer)
    }
    @invalid_model = "INVALID MODEL" # fails requested_model format -> early save failure, no Temporal
  end

  teardown { teardown_authz }

  test "show (landing) is a project read" do
    assert_project_read { get company_project_aixle_builder_path(@project) }
  end

  test "show_session is a project read (each member reads its own session)" do
    assert_project_read do |role|
      get company_project_aixle_builder_session_path(@project, @sessions.fetch(role, @sessions[:owner]))
    end
  end

  # start is write-gated; the invalid model forces an early validation failure so
  # the allowed roles redirect back to the builder (302) without reaching Temporal.
  # The denial (viewer) is proven separately by the harness's :denied alert check.
  test "start is a project write (invalid model redirects, no Temporal)" do
    assert_project_write(allowed: :redirect) do
      post company_project_aixle_builder_start_path(@project), params: { preferred_model: @invalid_model }
    end
  end

  test "finish is a project write (each member finishes its own started session)" do
    assert_project_write do |role|
      post company_project_aixle_builder_finish_path(@project, @sessions.fetch(role, @sessions[:owner]))
    end
  end
end
