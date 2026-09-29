# frozen_string_literal: true

class SessionAdmissionService
  class Stopped < StandardError; end

  # A permit that does not match the reservation it names. Deliberately a
  # subclass, so every existing `rescue Stopped` keeps treating it the same way —
  # what it buys is the ability to tell it apart from the three benign reasons a
  # permit is closed. Somebody closing a dialog or cancelling a run is expected
  # control flow; a token that no longer matches means something else restarted
  # this launch, which is a fault and must keep its report.
  class StalePermit < Stopped; end
  class UncertainOperation < StandardError; end

  # How many pools one drain pass may examine. Project/user mode creates one pool
  # per project and per user, so an unbounded scan would row-lock the whole
  # installation on every enqueue.
  POOL_SCAN_LIMIT = 200

  # A session outside a project is an agent login: interactive, short, and
  # launched by a person watching a dialog. It queues per user so that two
  # logins (say Claude and Codex) start at once while a runaway loop cannot
  # fill the cluster, and it draws on no company's budget.
  AUTH_POOL_LIMIT = 2

  class << self
    # The WRITER lock (AD-3). Serializes the small admission decisions — grant,
    # cancel, release, policy and pool-limit changes — so occupancy can never be
    # read stale between the count and the grant.
    #
    # Nothing slow belongs inside it: no runtime calls, no Temporal RPCs, and no
    # record save that touches half a dozen join tables.
    def transaction(&block)
      SessionAdmissionPolicy.current
      SessionAdmissionPolicy.transaction do
        policy = SessionAdmissionPolicy.lock.find(1)
        yield policy
      end
    end

    def enqueue!(session)
      transaction do |policy|
        next session.session_admission if session.session_admission

        ensure_run_active!(session)
        key, limit = pool_configuration(policy, session)
        pool = SessionAdmissionPool.create_or_find_by!(key: key) do |p|
          p.limit = limit
          p.policy_revision = policy.revision
        end
        pool.lock!
        session.enqueue!
        SessionAdmission.create!(terminal_session: session, session_admission_pool: pool)
      end
    end

    def drain!(limit: 100)
      granted = []
      transaction do |policy|
        # Materialised first so the budget resolves every pool's company in one
        # query instead of one per pool.
        pools = pools_with_waiting_head.to_a
        budget = SessionAdmissionBudget.new(pools.map(&:key))

        pools.each do |pool|
          pool.lock!
          candidates = pool.session_admissions.unreleased.where(admitted_at: nil, stop_requested_at: nil).order(:id)
          head = candidates.first
          next unless head

          key, cap = pool_configuration(policy, head.terminal_session)
          # A head whose scope no longer maps to this pool is an installation pool
          # left over from when the installation limit selected which pool a
          # session belonged to. Nothing is ever added to one again, so it is
          # drained against the cap it was created with rather than re-scoped.
          cap = pool.limit unless key == pool.key

          pool.update!(limit: cap, policy_revision: policy.revision) if key == pool.key
          available = budget.clamp(cap - pool.session_admissions.occupied.count, pool.key)
          take = [ available, limit - granted.size ].min.clamp(0, limit)
          candidates.limit(take).each do |admission|
            session = admission.terminal_session
            begin
              ensure_run_active!(session)
            rescue Stopped
              close_queued!(admission)
              next
            end
            admission.update!(admitted_at: Time.current, permit_token: SecureRandom.uuid, wait_reason: "dispatch_pending")
            granted << admission.id
            budget.spend!(pool.key)
          end
          # No break on an exhausted remainder: a reserved project further down the
          # scan is still owed its own slots, and they are not drawn from it.
          break if granted.size >= limit
        end
      end
      granted
    end

    # `outcome` is the verdict written on a session that has not ended yet:
    # "cancelled" for a stop a person or the run asked for, "failed" for a
    # watchdog's. A session that already ended keeps its own: cancelling a run
    # does not relabel its finished steps.
    def cancel!(session, outcome: "cancelled")
      transaction do
        admission = session.session_admission&.lock!
        next unless admission
        admission.update!(stop_requested_at: admission.stop_requested_at || Time.current)
        verdict = session.reload.state.in?(TerminalSession::TERMINAL_STATES) ? nil : outcome
        if admission.admitted_at.nil? || (admission.launch_state == "pending" && admission.claimed_at.nil?)
          close_queued!(admission, verdict)
        elsif verdict
          conclude!(session, verdict)
        end
      end
      session.reload
    end

    # Read-only permit check. Deliberately takes no lock: it is called on every
    # container phase, and a stop marker that lands a millisecond later is
    # caught by #begin_operation!, which does lock.
    def permit!(admission_id, token)
      admission = SessionAdmission.find(admission_id)
      # Split by reason rather than raising one error for four conditions: three
      # of these are somebody stopping their own work, and one is an anomaly.
      # Reporting them together meant either losing the anomaly in the noise or
      # paging on ordinary cancellations.
      raise StalePermit, "Session admission permit is stale" if admission.permit_token != token
      if admission.released_at || admission.stop_requested_at || admission.admitted_at.nil?
        raise Stopped, "Session admission is closed"
      end
      ensure_run_active!(admission.terminal_session)
      admission
    end

    # The fencing point for anything that may reach the runtime. Locks the
    # admission — not the installation-wide policy row — because the operation
    # ledger is per-admission and this runs on every create/start/exec phase.
    def begin_operation!(admission_id, token, phase)
      SessionAdmission.transaction do
        admission = SessionAdmission.lock.find(admission_id)
        permit!(admission.id, token)
        operation = admission.session_runtime_operations.find_by(phase: phase)
        if operation
          return operation if operation.state == "completed"
          unless operation.state == "retryable" || operation.replayable?
            # Only the phases that cannot be repeated get here now, so the message
            # can stop guessing: `exec` holds no reservation (MATERIALIZING_PHASES
            # excludes it), and saying otherwise sent operators after a leak that
            # does not exist.
            raise UncertainOperation, "Unresolved #{phase}; #{operation.reservation_note}"
          end
          operation.update!(state: "in_flight", error: nil)
        else
          operation = admission.session_runtime_operations.create!(phase: phase)
        end
        operation
      end
    end

    def release!(admission)
      transaction do
        admission.reload.lock!
        next if admission.released_at
        # Only an operation that can still put a workload on the cluster keeps
        # the slot (SessionRuntimeOperation::MATERIALIZING_PHASES). Callers
        # release after confirming absence, which is what makes an unresolved
        # `exec` harmless: it has nothing left to run inside.
        raise UncertainOperation, "Runtime operation unresolved" if admission.session_runtime_operations.pinning.exists?
        admission.update!(released_at: Time.current, launch_state: "closed", wait_reason: nil)
      end
    end

    def ensure_run_active!(session)
      run = session.step_run&.workflow_run
      raise Stopped, "Workflow cancelled" if run && (run.stop_requested_at || run.state.in?(%w[cancelled failed completed]))
    end

    private

    # Only pools that actually have someone waiting are worth locking, and only
    # a bounded page of them per pass — the minutely reconciler picks up the
    # rest.
    def pools_with_waiting_head
      SessionAdmissionPool
        .where(id: SessionAdmission.unreleased.where(admitted_at: nil, stop_requested_at: nil).select(:session_admission_pool_id))
        .order(:id)
        .limit(POOL_SCAN_LIMIT)
    end

    def close_queued!(admission, verdict = "cancelled")
      admission.update!(released_at: Time.current, launch_state: "closed", wait_reason: nil)
      conclude!(admission.terminal_session, verdict) if verdict
    end

    # Through the state machine, so the ending is recorded like any other. A
    # failure's wake-up of the parent run waits for the commit (on_failed).
    def conclude!(session, verdict)
      verdict == "failed" ? session.fail! : session.cancel!
    end

    # Every admitted session belongs to exactly one pool: its project's, or for an
    # agent login its user's. The company limit is a ceiling over the project
    # pools, spent in #drain!.
    def pool_configuration(_policy, session)
      return [ "user:#{session.user_id}", AUTH_POOL_LIMIT ] if session.project_id.blank?

      configured = SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: session.project_id)
      [ "project:#{session.project_id}", configured&.max_sessions || SessionAdmissionPolicy.scope_default("Project") ]
    end
  end
end
