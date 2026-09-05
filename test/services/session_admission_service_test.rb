# frozen_string_literal: true

require "test_helper"

class SessionAdmissionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
  end

  teardown { restore_scope_defaults }

  def enqueue(user: @user, project: nil)
    session = create(:terminal_session, user: user, project: project)
    SessionAdmissionService.enqueue!(session)
  end

  test "installation capacity reserves one slot and admits FIFO after cancellation" do
    first = enqueue
    second = enqueue
    assert_equal [ first.id ], SessionAdmissionService.drain!
    assert_equal 1, SessionAdmission.occupied.count
    assert_nil second.reload.admitted_at
    assert_nil second.terminal_session.started_at
    SessionAdmissionService.cancel!(first.terminal_session)
    assert_equal [ second.id ], SessionAdmissionService.drain!
    assert_equal "cancelled", first.terminal_session.reload.state
  end

  test "claimed launch cancellation retains slot until cleanup" do
    first = enqueue
    second = enqueue
    SessionAdmissionService.drain!
    first.reload.update!(launch_state: "claimed", claimed_at: Time.current)
    SessionAdmissionService.cancel!(first.terminal_session)
    assert_nil first.reload.released_at
    assert_empty SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at
    assert_raises(SessionAdmissionService::Stopped) do
      SessionAdmissionService.transaction { SessionAdmissionService.permit!(first.id, first.permit_token) }
    end
  end

  test "uncertain runtime operations cannot replay or release their slot" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    operation = SessionAdmissionService.begin_operation!(admission.id, token, "exec")
    operation.update!(state: "uncertain")
    assert_raises(SessionAdmissionService::UncertainOperation) { SessionAdmissionService.begin_operation!(admission.id, token, "exec") }
    assert_raises(SessionAdmissionService::UncertainOperation) { SessionAdmissionService.release!(admission) }
    assert_nil admission.reload.released_at
  end

  test "lowering capacity does not evict existing reservations" do
    SessionAdmissionPolicy.sync!(installation_limit: 2)
    first = enqueue
    second = enqueue
    third = enqueue
    assert_equal [ first.id, second.id ], SessionAdmissionService.drain!
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    assert_empty SessionAdmissionService.drain!
    assert_equal 2, SessionAdmission.occupied.count
    assert_nil third.reload.admitted_at
  end

  test "unset installation cap gives independent project and user pools" do
    with_scope_defaults(project: 1, user: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    project = create(:project, owner: @user, company: @user.companies.first)
    project_first = enqueue(project: project)
    project_second = enqueue(project: project)
    personal = enqueue
    assert_equal [ project_first.id, personal.id ], SessionAdmissionService.drain!
    assert_nil project_second.reload.admitted_at
  end

  test "a changed scope default takes effect without writing policy" do
    with_scope_defaults(project: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    project = create(:project, owner: @user, company: @user.companies.first)
    first = enqueue(project: project)
    second = enqueue(project: project)
    assert_equal [ first.id ], SessionAdmissionService.drain!

    revision = SessionAdmissionPolicy.current.revision
    with_scope_defaults(project: 2)

    assert_equal [ second.id ], SessionAdmissionService.drain!
    assert_equal revision, SessionAdmissionPolicy.current.revision,
      "the size of a scope queue is deployment configuration, not policy state"
  end

  test "an unusable scope default falls back instead of wedging every queue" do
    ENV["SESSION_PROJECT_CONCURRENCY_DEFAULT"] = "lots"
    @_scope_defaults_restore = { "SESSION_PROJECT_CONCURRENCY_DEFAULT" => nil, "SESSION_USER_CONCURRENCY_DEFAULT" => nil }

    assert_equal 4, SessionAdmissionPolicy.scope_default("Project")
    assert_equal 2, SessionAdmissionPolicy.scope_default("User"), "an unset variable keeps its own fallback"
  end

  test "a scope override beats the deployment default, which beats nothing" do
    with_scope_defaults(project: 1, user: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    project = create(:project, owner: @user, company: @user.companies.first)
    SessionConcurrencyLimit.set!(scope: project, max_sessions: 2)

    first = enqueue(project: project)
    second = enqueue(project: project)
    third = enqueue(project: project)

    assert_equal [ first.id, second.id ], SessionAdmissionService.drain!
    assert_nil third.reload.admitted_at, "the override raises this project's cap, not the default"
    assert_equal 2, SessionAdmissionPool.find_by(key: "project:#{project.id}").limit
  end

  test "a session in a project draws on the project pool, not its launcher's" do
    with_scope_defaults(project: 1, user: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    project = create(:project, owner: @user, company: @user.companies.first)
    other = create(:user, :with_company)
    create(:company_membership, user: other, company: project.company, state: :active)

    mine = enqueue(project: project)
    theirs = enqueue(user: other, project: project)

    assert_equal [ mine.id ], SessionAdmissionService.drain!
    assert_nil theirs.reload.admitted_at, "two people in one project share that project's cap"
    assert_equal "project:#{project.id}", theirs.session_admission_pool.key
  end

  test "raising a scope limit admits the queue without waiting for reconciliation" do
    with_scope_defaults(project: 1, user: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    project = create(:project, owner: @user, company: @user.companies.first)
    first = enqueue(project: project)
    second = enqueue(project: project)
    SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at

    SessionConcurrencyLimit.set!(scope: project, max_sessions: 2)

    assert second.reload.admitted_at, "the write itself wakes the queue"
    assert_equal [ first.id, second.id ], SessionAdmission.occupied.order(:id).pluck(:id)
  end

  test "disabling admission with queued work is rejected" do
    enqueue
    assert_raises(ArgumentError) { SessionAdmissionPolicy.sync!(enabled: false, installation_limit: 1) }
    assert SessionAdmissionPolicy.current.enabled?
  end

  test "queued session finish cancels without sending runtime commands" do
    admission = enqueue
    TemporalService.expects(:cancel_workflow).never
    SessionService.finish(session: admission.terminal_session)
    assert_equal "cancelled", admission.terminal_session.reload.state
    assert admission.reload.released_at
  end

  test "unreleased sessions cannot be deleted but cancelled queue entries can" do
    admission = enqueue
    session = admission.terminal_session
    assert_not session.destroy
    SessionAdmissionService.cancel!(session)
    assert session.destroy
    assert_not SessionAdmission.exists?(admission.id)
  end
end
