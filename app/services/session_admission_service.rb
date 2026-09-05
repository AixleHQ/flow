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

        pools_with_waiting_head.each do |pool|
          pool.lock!
          candidates = pool.session_admissions.unreleased.where(admitted_at: nil, stop_requested_at: nil).order(:id)
          head = candidates.first
          next unless head

          key, cap = pool_configuration(policy, head.terminal_session)
          # A head whose scope no longer maps to this pool means the policy mode
          # changed under us. Stamping the other mode's cap here would silently
          # re-scope live capacity, so leave the pool alone for the operator.
          next unless key == pool.key

          pool.update!(limit: cap, policy_revision: policy.revision)
          available = cap - pool.session_admissions.occupied.count
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
          end
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
        raise UncertainOperation, "Runtime operation unresolved" if admission.session_runtime_operations.where(state: %w[in_flight uncertain]).exists?
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

    def pool_configuration(policy, session)
      return [ "installation:default", policy.installation_limit ] if policy.installation_limit
      type, id, default = session.project_id ? [ "Project", session.project_id, policy.project_default ] : [ "User", session.user_id, policy.user_default ]
      [ "#{type.downcase}:#{id}", SessionConcurrencyLimit.find_by(scope_type: type, scope_id: id)&.max_sessions || default ]
    end
  end
end
