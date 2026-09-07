# frozen_string_literal: true

require "test_helper"

# Per-scope caps are the one part of the admission policy that is not deployment
# configuration, so it is the one part that belongs in the admin.
class Admin::SessionConcurrencyLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    # A super_admin is a platform role and gets no membership, so the project
    # needs an ordinary member to own it.
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company,
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
    @owner = create(:user, company: @company)
    @project = create(:project, owner: @owner, company: @company)
    with_scope_defaults(project: 1, user: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
  end

  teardown { restore_scope_defaults }

  test "index lists the scope overrides" do
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 4)

    get admin_session_concurrency_limits_path

    assert_response :success
    assert_match(/Project/, response.body)
    assert_match(/4/, response.body)
  end

  test "creating a limit moves the policy revision so pools recompute their cap" do
    before = SessionAdmissionPolicy.current.revision

    post admin_session_concurrency_limits_path, params: {
      session_concurrency_limit: { scope_type: "Project", scope_id: @project.id, max_sessions: 3 }
    }

    assert_equal 3, SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: @project.id).max_sessions
    assert_operator SessionAdmissionPolicy.current.revision, :>, before,
      "a cap edited in the UI must invalidate the cached pool limit"
  end

  test "raising a limit in the admin admits what was queued behind the old one" do
    session = create(:terminal_session, user: @owner, project: @project)
    queued = create(:terminal_session, user: @owner, project: @project)
    SessionAdmissionService.enqueue!(session)
    admission = SessionAdmissionService.enqueue!(queued)
    SessionAdmissionService.drain!
    assert_nil admission.reload.admitted_at

    post admin_session_concurrency_limits_path, params: {
      session_concurrency_limit: { scope_type: "Project", scope_id: @project.id, max_sessions: 2 }
    }

    assert admission.reload.admitted_at, "the queue should not wait for the next reconciliation"
  end

  test "a scope that does not exist is rejected rather than stored as a dead row" do
    post admin_session_concurrency_limits_path, params: {
      session_concurrency_limit: { scope_type: "Project", scope_id: 0, max_sessions: 3 }
    }

    assert_empty SessionConcurrencyLimit.where(scope_id: 0)
  end
end
