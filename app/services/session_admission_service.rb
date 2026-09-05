# frozen_string_literal: true

class SessionAdmissionService
  class Stopped < StandardError; end
  class UncertainOperation < StandardError; end

  class << self
    # Policy UPDATE deliberately serializes the small admission transactions.
    # This also gives run cancellation, scope changes and permits one lock order.
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
        pool = SessionAdmissionPool.find_or_create_by!(key: key) { |p| p.limit = limit; p.policy_revision = policy.revision }
        pool.lock!
        session.update!(state: "queued", queued_at: Time.current)
        SessionAdmission.create!(terminal_session: session, session_admission_pool: pool)
      end
    end

    def drain!(limit: 100)
      granted = []
      transaction do |policy|
        next if !policy.enabled? || policy.paused?
        SessionAdmissionPool.order(:id).each do |pool|
          pool.lock!
          candidates = pool.session_admissions.unreleased.where(admitted_at: nil, stop_requested_at: nil).order(:id)
          head = candidates.first
          next unless head
          _, cap = pool_configuration(policy, head.terminal_session)
          pool.update!(limit: cap, policy_revision: policy.revision)
          available = cap - pool.session_admissions.occupied.count
          candidates.limit([ available, limit - granted.size ].min.clamp(0, limit)).each do |admission|
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

    def permit!(admission_id, token)
      admission = SessionAdmission.find(admission_id)
      raise Stopped, "Session admission is closed" if admission.released_at || admission.stop_requested_at || admission.permit_token != token || admission.admitted_at.nil?
      ensure_run_active!(admission.terminal_session)
      admission
    end

    def begin_operation!(admission_id, token, phase)
      transaction do
        admission = permit!(admission_id, token)
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
