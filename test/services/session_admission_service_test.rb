# frozen_string_literal: true

require "test_helper"

class SessionAdmissionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    with_admission(project: 1)
  end

  # Every queued session belongs to a project — that is what the queue is for.
  # Pass `project: nil` only to exercise the sessions that are exempt from it.
  def enqueue(user: @user, project: @project)
    session = create(:terminal_session, user: user, project: project)
    SessionAdmissionService.enqueue!(session)
  end

  test "a full queue reserves one slot and admits FIFO after cancellation" do
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

  # Every worker roll that interrupted a create — spot reclaim, OOM, a rolling
  # deploy — used to kill the session on the retry: the operation was left
  # in_flight, and begin_operation! refused anything that was not `retryable`.
  # Nothing repaired it either; the reconciler only looks at closed workflows, and
  # this one is alive and retrying its own activity.
  test "an interrupted create is made again instead of killing the session" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "create_container")

    replayed = SessionAdmissionService.begin_operation!(admission.id, token, "create_container")

    assert_equal "in_flight", replayed.state
    assert_equal 1, admission.session_runtime_operations.where(phase: "create_container").count
  end

  test "an interrupted start is made again too" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "start_container").update!(state: "uncertain")

    assert_equal "in_flight", SessionAdmissionService.begin_operation!(admission.id, token, "start_container").state
  end

  # The message used to be interpolated blindly, so an unaccountable exec — which
  # holds no reservation at all — told the operator capacity was being retained
  # and sent them hunting a leak that does not exist.
  test "the refusal to replay an exec does not claim a reservation is held" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    SessionAdmissionService.begin_operation!(admission.id, token, "exec").update!(state: "uncertain")

    error = assert_raises(SessionAdmissionService::UncertainOperation) do
      SessionAdmissionService.begin_operation!(admission.id, token, "exec")
    end

    assert_match(/no reservation is held/, error.message)
    assert_no_match(/reservation retained/, error.message)
  end

  # == permit reasons ==

  test "a permit closed by somebody stopping their own work is an ordinary stop" do
    admission = enqueue
    SessionAdmissionService.drain!
    token = admission.reload.permit_token
    admission.update!(stop_requested_at: Time.current)

    error = assert_raises(SessionAdmissionService::Stopped) { SessionAdmissionService.permit!(admission.id, token) }

    assert_not_kind_of SessionAdmissionService::StalePermit, error
  end

  # Something else restarted this launch. It is still non-retryable, and it still
  # reaches every existing `rescue Stopped` — but it is a fault, and it must not
  # be filed with the cancellations.
  test "a permit that no longer matches the reservation is reported as stale" do
    admission = enqueue
    SessionAdmissionService.drain!

    assert_raises(SessionAdmissionService::StalePermit) do
      SessionAdmissionService.permit!(admission.id, "a-token-from-another-launch")
    end
    assert_kind_of SessionAdmissionService::Stopped,
      SessionAdmissionService::StalePermit.new("still caught by every existing rescue")
  end

  test "lowering capacity does not evict existing reservations" do
    with_company_limit(@company, 2)
    first = enqueue
    second = enqueue
    third = enqueue
    assert_equal [ first.id, second.id ], SessionAdmissionService.drain!
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 1)
    assert_empty SessionAdmissionService.drain!
    assert_equal 2, SessionAdmission.occupied.count
    assert_nil third.reload.admitted_at
  end

  test "with no company limit each project has its own independent queue" do
    with_admission(project: 1)
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
    with_company_limit(@company, 1)

    assert_nil enqueue(project: nil)
    assert_equal 0, SessionAdmission.count
  end

  test "an exempt session does not consume the company's capacity" do
    with_company_limit(@company, 1)
    enqueue(project: nil)
    queued = enqueue

    assert_equal [ queued.id ], SessionAdmissionService.drain!
  end

  # Both tiers apply at once: the company bounds the total, the project bounds
  # its own share of it.
  test "a project's own limit and its company's limit both apply" do
    with_company_limit(@company, 3, project: 2)
    other_project = create(:project, owner: @user, company: @company)
    3.times { enqueue }
    3.times { enqueue(project: other_project) }

    granted = SessionAdmissionService.drain!

    assert_equal 3, granted.size, "the company bounds the total"
    mine = SessionAdmission.occupied.joins(:session_admission_pool)
                           .where(session_admission_pools: { key: "project:#{@project.id}" }).count
    assert_equal 2, mine, "and each project is still bounded by its own limit"
  end

  # The point of a reservation: it is capacity the project can count on, not a
  # number on a screen. An idle reservation is NOT lent to whoever asks first.
  test "a reserved project reaches its limit even after the shared pool is full" do
    with_company_limit(@company, 4, project: 10)
    reserved_project = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: reserved_project, max_sessions: 1)

    # @project has no limit of its own, so it shares the 3 nobody reserved.
    4.times { enqueue }
    SessionAdmissionService.drain!

    assert_equal 3, SessionAdmission.occupied.count, "an unreserved project may not occupy the reservation"

    mine = enqueue(project: reserved_project)

    assert_equal [ mine.id ], SessionAdmissionService.drain!, "the reservation was still there for its owner"
    assert_equal 4, SessionAdmission.occupied.count, "and the company limit is still the bound"
  end

  test "unreserved projects share only what the reservations leave" do
    with_company_limit(@company, 5, project: 10)
    reserved_project = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: reserved_project, max_sessions: 3)
    5.times { enqueue }

    assert_equal 2, SessionAdmissionService.drain!.size, "5 less the 3 reserved leaves 2 to share"
  end

  # Clearing a project's limit hands its capacity back to everyone else.
  test "a project without a limit of its own draws on the shared pool" do
    with_company_limit(@company, 3, project: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 2)
    other_project = create(:project, owner: @user, company: @company)
    3.times { enqueue(project: other_project) }
    assert_equal 1, SessionAdmissionService.drain!.size, "only 1 of 3 is unreserved"

    # The destroy wakes the queue itself (publish_change), so the capacity is
    # already handed over by the time this returns — asserting on a second drain
    # would find nothing left and prove the opposite of what it looks like.
    SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: @project.id).destroy

    assert_equal 3, SessionAdmission.occupied.count, "giving the reservation back releases it to the pool"
  end

  # A reservation is validated against its company when it is saved, but the
  # company may be lowered underneath it afterwards — a downgrade must not be
  # blocked by how the customer divided their capacity. The company then wins: a
  # reservation is honoured only as far as it fits, rather than the company limit
  # quietly becoming advisory. QueueHealthCheck reports the state.
  test "a company lowered below its reservations still bounds its projects" do
    with_company_limit(@company, 5, project: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 4)
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 3)
    4.times { enqueue }

    assert_equal 3, SessionAdmissionService.drain!.size, "the company limit is never advisory"
  end

  test "the company limit stops a project short of its own limit" do
    with_company_limit(@company, 2, project: 5)
    3.times { enqueue }

    assert_equal 2, SessionAdmissionService.drain!.size
  end

  test "raising a company limit takes effect without a cutover" do
    # Pinned so the company is the binding constraint: left to the ambient
    # default, the project's own pool fills first and the test proves nothing
    # about the company tier.
    with_company_limit(@company, 1, project: 5)
    first = enqueue
    second = enqueue
    SessionAdmissionService.drain!
    assert_nil second.reload.admitted_at

    # Writing the row wakes the queue itself (publish_change), so the raise is
    # already spent by the time this returns — asserting on a later drain would
    # find nothing and prove the opposite of what it looks like.
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 2)

    assert second.reload.admitted_at, "the raise admitted what was waiting"
    assert first.reload.admitted_at, "and must not disturb what is already running"
  end

  test "a changed scope default takes effect without writing policy" do
    with_admission(project: 1)
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
    # A ConfigMap typo, which must fall back rather than wedge every queue.
    with_scope_defaults(project: "lots")

    assert_equal 4, SessionAdmissionPolicy.scope_default("Project")
  end

  test "a scope override beats the deployment default, which beats nothing" do
    with_admission(project: 1)
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
    with_admission(project: 1)
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
    with_admission(project: 1)
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
    assert_raises(ArgumentError) { SessionAdmissionPolicy.sync!(enabled: false) }
    assert SessionAdmissionPolicy.current.enabled?
  end

  test "queued session finish cancels without sending runtime commands" do
    admission = enqueue
    TemporalService.expects(:cancel_workflow).never
    SessionService.finish(session: admission.terminal_session)
    assert_equal "cancelled", admission.terminal_session.reload.state
    assert admission.reload.released_at
  end

  # A watchdog's verdict is a failure. Recording it as `cancelled` made the parent
  # run cancel itself (WorkflowExecutionWorkflowV2), skipping on_failure.
  test "a watchdog failing an admitted session records failed and still tears the runtime down" do
    admission = enqueue
    SessionAdmissionService.drain!
    admission.reload.update!(launch_state: "claimed", claimed_at: Time.current)
    session = admission.terminal_session
    TemporalService.expects(:cancel_workflow).with(session.workflow_id).once

    SessionService.fail_session(session: session, error_message: "No output for 30 minutes")

    assert_equal "failed", session.reload.state
    assert_equal "No output for 30 minutes", session.error_message
    assert admission.reload.stop_requested_at
    assert_nil admission.released_at, "confirmed cleanup, not the verdict, returns the slot"
  end

  test "a watchdog failing a session still in the queue closes its place as failed" do
    admission = enqueue
    TemporalService.expects(:cancel_workflow).never

    SessionService.fail_session(session: admission.terminal_session, error_message: "Stale session")

    assert_equal "failed", admission.terminal_session.reload.state
    assert admission.reload.released_at
  end

  test "cancelling does not relabel a session that already ended" do
    admission = enqueue
    SessionAdmissionService.drain!
    admission.reload.update!(launch_state: "acknowledged")
    session = admission.terminal_session
    session.update!(state: "finished", finished_at: Time.current)

    SessionAdmissionService.cancel!(session)

    assert_equal "finished", session.reload.state
    assert admission.reload.stop_requested_at
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
