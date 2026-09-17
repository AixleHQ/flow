# frozen_string_literal: true

class SessionAdmissionService
  class Stopped < StandardError; end
  class UncertainOperation < StandardError; end

  # How many pools one drain pass may examine. Project/user mode creates one pool
  # per project and per user, so an unbounded scan would row-lock the whole
  # installation on every enqueue.
  POOL_SCAN_LIMIT = 200

  class << self
    # The WRITER lock (AD-3). Serializes the small admission decisions — grant,
    # cancel, release, policy and pool-limit changes — so occupancy can never be
    # read stale between the count and the grant.
    #
    # Nothing slow belongs inside it: no runtime calls, no Temporal RPCs, and no
    # record save that touches half a dozen join tables. Callers that only need
    # to know whether admission is on use #policy instead.
    def transaction(&block)
      SessionAdmissionPolicy.current
      SessionAdmissionPolicy.transaction do
        policy = SessionAdmissionPolicy.lock.find(1)
        yield policy
      end
    end

    # Unlocked read for branch decisions ("is admission on at all"). Every path
    # that acts on the answer re-checks it under the writer lock, so a policy
    # flip racing with this read costs at most one legacy-path launch — which
    # the cutover drain in SessionAdmissionPolicy.sync! already forbids.
    def policy = SessionAdmissionPolicy.current

    # Returns the admission, or nil when admission is disabled and the caller
    # should take the legacy launch path.
    def enqueue!(session)
      # The queue is a property of a project: a slot is allocated to one, waited
      # for in one, and shown in one's settings. A session with no project has no
      # queue to join — in practice that is an agent login (`auth_setup`), which
      # is short, interactive, and launched by a person watching a dialog. Nil
      # sends it down the launch path that needs no reservation.
      return nil if session.project_id.blank?

      # Asked before the writer lock so that a schema that is not there yet
      # answers "no queue" instead of failing the launch. The authoritative
      # re-check still happens under the lock below.
      return nil unless SessionAdmissionPolicy.enabled?

      transaction do |policy|
        next session.session_admission if session.session_admission
        next nil unless policy.enabled?

        ensure_run_active!(session)
        key, limit = pool_configuration(policy, session)
        pool = SessionAdmissionPool.create_or_find_by!(key: key) do |p|
          p.limit = limit
          p.policy_revision = policy.revision
        end
        pool.lock!
        session.update!(state: "queued", queued_at: Time.current)
        SessionAdmission.create!(terminal_session: session, session_admission_pool: pool)
      end
    end

    def drain!(limit: 100)
      granted = []
      transaction do |policy|
        next if !policy.enabled? || policy.paused?

        # An explicit project limit is a RESERVATION: the project can always reach
        # it, because nothing else is ever allowed to occupy it. That is what the
        # budget rule buys — the reservations are validated to fit inside the
        # ceiling, so honouring each one in full can never exceed it.
        #
        # Everyone else shares what is left over. Counting that pool against total
        # occupancy instead would hand a reserved project's idle slots to whoever
        # asked first, and the reservation would be a number on a screen rather
        # than capacity anybody can count on.
        reserved_keys = SessionConcurrencyLimit.where(scope_type: "Project")
                                               .pluck(:scope_id).map { |id| "project:#{id}" }
        free_headroom = if policy.installation_limit
          unreserved = SessionAdmission.occupied.joins(:session_admission_pool)
                                       .where.not(session_admission_pools: { key: reserved_keys }).count
          [ policy.installation_limit - SessionConcurrencyLimit.sum(:max_sessions) - unreserved, 0 ].max
        end

        pools_with_waiting_head.each do |pool|
          pool.lock!
          candidates = pool.session_admissions.unreleased.where(admitted_at: nil, stop_requested_at: nil).order(:id)
          head = candidates.first
          next unless head

          key, cap = pool_configuration(policy, head.terminal_session)
          # A head whose scope no longer maps to this pool is an installation pool
          # left over from when the installation limit selected a mode instead of
          # being a ceiling. Nothing is ever added to one again, so it is drained
          # against the cap it was created with rather than re-scoped or stranded.
          cap = pool.limit unless key == pool.key

          pool.update!(limit: cap, policy_revision: policy.revision) if key == pool.key
          available = cap - pool.session_admissions.occupied.count
          # A reserved project draws only on its own reservation and is bounded by
          # nothing else; an unreserved one draws on the shared remainder.
          reserved = pool.key.in?(reserved_keys)
          available = [ available, free_headroom ].min if free_headroom && !reserved
          budget = [ available, limit - granted.size ].min.clamp(0, limit)
          candidates.limit(budget).each do |admission|
            session = admission.terminal_session
            begin
              ensure_run_active!(session)
            rescue Stopped
              close_queued!(admission)
              next
            end
            admission.update!(admitted_at: Time.current, permit_token: SecureRandom.uuid, wait_reason: "dispatch_pending")
            granted << admission.id
            # Spend the shared remainder as we go: two unreserved pools drained in
            # one pass must not each be told the whole remainder is free.
            free_headroom -= 1 if free_headroom && !reserved
          end
          # No break on an exhausted remainder: a reserved project further down the
          # scan is still owed its own slots, and they are not drawn from it.
          break if granted.size >= limit
        end
      end
      granted
    end

    def cancel!(session)
      transaction do
        admission = session.session_admission&.lock!
        next unless admission
        admission.update!(stop_requested_at: admission.stop_requested_at || Time.current)
        if admission.admitted_at.nil? || (admission.launch_state == "pending" && admission.claimed_at.nil?)
          close_queued!(admission)
        else
          session.update!(state: "cancelled", finished_at: Time.current)
        end
      end
      session.reload
    end

    # Read-only permit check. Deliberately takes no lock: it is called on every
    # container phase, and a stop marker that lands a millisecond later is
    # caught by #begin_operation!, which does lock.
    def permit!(admission_id, token)
      admission = SessionAdmission.find(admission_id)
      raise Stopped, "Session admission is closed" if admission.released_at || admission.stop_requested_at || admission.permit_token != token || admission.admitted_at.nil?
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
          raise UncertainOperation, "Unresolved #{phase}; reservation retained" unless operation.state == "retryable"
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

    def close_queued!(admission)
      admission.update!(released_at: Time.current, launch_state: "closed", wait_reason: nil)
      admission.terminal_session.update!(state: "cancelled", finished_at: Time.current)
    end

    # Every admitted session belongs to exactly one pool: its project's. The
    # installation limit is not one of the choices any more — it is a ceiling over
    # all of them, spent in #drain!. A session with no project never gets here;
    # #enqueue! sends it down the unreserved launch path.
    def pool_configuration(_policy, session)
      configured = SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: session.project_id)
      [ "project:#{session.project_id}", configured&.max_sessions || SessionAdmissionPolicy.scope_default("Project") ]
    end
  end
end
