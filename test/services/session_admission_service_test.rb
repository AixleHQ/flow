# frozen_string_literal: true

require "test_helper"

class SessionAdmissionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
  end

  teardown { restore_scope_defaults }

  # Every queued session belongs to a project — that is what the queue is for.
  # Pass `project: nil` only to exercise the sessions that are exempt from it.
  def enqueue(user: @user, project: @project)
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

  # Replaying a phase nobody can account for would risk doing its side effect
  # twice — for exec, launching the agent twice — so the phase refuses whatever
  # it costs the session. This is separate from what the operation costs the
  # POOL, which the two tests below draw the line for.
  test "an uncertain runtime operation is never replayed" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "exec").update!(state: "uncertain")

    assert_raises(SessionAdmissionService::UncertainOperation) do
      SessionAdmissionService.begin_operation!(admission.id, token, "exec")
    end
  end

  # AD-5 keeps a slot so a late Pod never finds its seat handed to someone else,
  # and only a create or a start can produce that Pod.
  test "an uncertain create keeps the reservation until an operator resolves it" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "create_container").update!(state: "uncertain")

    assert_raises(SessionAdmissionService::UncertainOperation) { SessionAdmissionService.release!(admission) }
    assert_nil admission.reload.released_at
  end

  # An exec acts inside a container, and callers release only after confirming
  # that container is gone — so a late one has nothing left to run and costs the
  # pool nothing. Holding the slot for it wedged the installation instead.
  test "an uncertain exec does not stand in the way of release" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "exec").update!(state: "uncertain")

    SessionAdmissionService.release!(admission)

    assert admission.reload.released_at
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

  test "unset installation cap gives each project its own independent queue" do
    with_scope_defaults(project: 1)
    SessionAdmissionPolicy.sync!(installation_limit: nil)
    other_project = create(:project, owner: @user, company: @user.companies.first)
    mine_first = enqueue
    mine_second = enqueue
    theirs = enqueue(project: other_project)

    assert_equal [ mine_first.id, theirs.id ], SessionAdmissionService.drain!
    assert_nil mine_second.reload.admitted_at, "one project filling up must not hold up another"
  end

  # The queue is a project feature: a slot is allocated to a project, waited for
  # in one and shown in one's settings. A session with no project — in practice an
  # agent login — has no queue to join and launches without a reservation.
  test "a session with no project is not queued at all" do
    SessionAdmissionPolicy.sync!(installation_limit: 1)

    assert_nil enqueue(project: nil)
    assert_equal 0, SessionAdmission.count
  end

  test "an exempt session does not consume the installation ceiling" do
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    enqueue(project: nil)
    queued = enqueue

    assert_equal [ queued.id ], SessionAdmissionService.drain!
  end

  # The point of the change: the installation limit and a project's own limit used
  # to be alternatives — setting one switched the other off. Both apply now.
  test "a project's own limit and the installation ceiling both apply" do
    with_scope_defaults(project: 2)
    SessionAdmissionPolicy.sync!(installation_limit: 3)
    other_project = create(:project, owner: @user, company: @user.companies.first)
    3.times { enqueue }
    3.times { enqueue(project: other_project) }

    granted = SessionAdmissionService.drain!

    assert_equal 3, granted.size, "the ceiling bounds the installation"
    mine = SessionAdmission.occupied.joins(:session_admission_pool)
                           .where(session_admission_pools: { key: "project:#{@project.id}" }).count
    assert_equal 2, mine, "and each project is still bounded by its own limit"
  end

  test "the installation ceiling stops a project short of its own limit" do
    with_scope_defaults(project: 5)
    SessionAdmissionPolicy.sync!(installation_limit: 2)
    3.times { enqueue }

    assert_equal 2, SessionAdmissionService.drain!.size
  end

  test "raising the installation ceiling no longer requires a drain" do
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    first = enqueue
    second = enqueue
    SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at

    # It used to re-home every live session, so it was refused while any ran.
    SessionAdmissionPolicy.sync!(installation_limit: 2)

    assert_equal [ second.id ], SessionAdmissionService.drain!
    assert first.reload.admitted_at, "a moved ceiling must not disturb what is already running"
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
    with_scope_defaults(project: 1)
    ENV["SESSION_PROJECT_CONCURRENCY_DEFAULT"] = "lots"

    assert_equal 4, SessionAdmissionPolicy.scope_default("Project")
  end

  test "a scope override beats the deployment default, which beats nothing" do
    with_scope_defaults(project: 1)
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
    with_scope_defaults(project: 1)
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
    with_scope_defaults(project: 1)
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
