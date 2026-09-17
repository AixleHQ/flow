# frozen_string_literal: true

require "test_helper"

# The ceiling has to be applicable by a deployment that has no shell, which is
# every deployed installation: after activation the admin page offers Pause and
# Resume and no way to apply a changed value at all.
class SessionAdmissionSyncJobTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
    SessionAdmissionPolicy.sync!(installation_limit: 4)
  end

  test "applies a ceiling changed in the deployment configuration" do
    with_scope_defaults(installation_limit: 9)

    assert_equal :applied, SessionAdmissionSyncJob.perform_now[:state]
    assert_equal 9, SessionAdmissionPolicy.current.installation_limit
  end

  test "moves the policy revision so pools recompute against the new ceiling" do
    before = SessionAdmissionPolicy.current.revision
    with_scope_defaults(installation_limit: 9)

    SessionAdmissionSyncJob.perform_now

    assert_operator SessionAdmissionPolicy.current.revision, :>, before
  end

  test "a raised ceiling admits what was waiting without a further pass" do
    with_scope_defaults(project: 10, installation_limit: 4)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    first = SessionAdmissionService.enqueue!(create(:terminal_session, user: @user, project: @project))
    second = SessionAdmissionService.enqueue!(create(:terminal_session, user: @user, project: @project))
    SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at

    SessionAdmissionSyncJob.perform_now

    assert second.reload.admitted_at, "the capacity exists now; waiting for the next tick wastes it"
    assert first.reload.admitted_at
  end

  test "an unchanged configuration is left alone" do
    with_scope_defaults(installation_limit: 4)

    assert_equal :unchanged, SessionAdmissionSyncJob.perform_now[:state]
    assert_equal 4, SessionAdmissionPolicy.current.installation_limit
  end

  test "clearing the variable removes the ceiling" do
    with_scope_defaults(installation_limit: nil)

    assert_equal :applied, SessionAdmissionSyncJob.perform_now[:state]
    assert_nil SessionAdmissionPolicy.current.installation_limit
  end

  # Reservations are promises this job must not be able to break by itself.
  test "a ceiling below what is already reserved is refused and the old one kept" do
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 4)
    with_scope_defaults(installation_limit: 2)

    result = SessionAdmissionSyncJob.perform_now

    assert_equal :refused, result[:state]
    assert_match(/below the 4 already reserved/, result[:detail])
    assert_equal 4, SessionAdmissionPolicy.current.installation_limit
  end

  # This runs every minute: a ConfigMap typo must be reported once per tick, not
  # raised, and certainly not applied as a zero.
  test "a value that is not a positive integer is reported, not applied" do
    with_scope_defaults(installation_limit: "lots")

    result = SessionAdmissionSyncJob.perform_now

    assert_equal :invalid, result[:state]
    assert_equal 4, SessionAdmissionPolicy.current.installation_limit
  end

  # Enabling is a cutover with a drain gate behind it, and a pause is somebody's
  # decision. A background job may do neither, whatever the configuration says.
  test "it never enables admission or clears a pause" do
    SessionAdmissionPolicy.current.update!(enabled: false, paused: true)
    with_scope_defaults(installation_limit: 9)

    SessionAdmissionSyncJob.perform_now

    policy = SessionAdmissionPolicy.current
    assert_equal 9, policy.installation_limit, "the number still moves"
    assert_not policy.enabled?, "but admission is not switched on by a background job"
    assert policy.paused?, "and a pause is not cleared by one"
  end
end
