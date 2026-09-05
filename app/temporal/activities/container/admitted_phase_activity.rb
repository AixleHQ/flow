# frozen_string_literal: true

module Activities
  module Container
    class AdmittedPhaseActivity < Base
      # Phases that can reach the container runtime, and therefore need a
      # durable operation record written before the request goes out (AD-5).
      RUNTIME_PHASES = %w[create_container start_container exec].freeze

      # Phases worth re-checking authorization for: everything that either
      # dials out on the user's behalf or hands them a shell.
      REVALIDATED_PHASES = %w[pull_image create_container exec].freeze

      # Failures that prove no request left this process, so the reservation can
      # stay usable instead of needing an operator. Every client we speak to
      # raises its own error class on the wire — Kubeclient::HttpError,
      # Docker::Error::*, Errno, OpenSSL, Timeout — so none of these can be a
      # half-sent RPC. Anything outside this list keeps AD-5's default: unknown
      # means the slot is held.
      NEVER_DISPATCHED = [
        ActiveRecord::ActiveRecordError, NoMethodError, NameError, ArgumentError, TypeError, KeyError
      ].freeze

      def run(input)
        admission = SessionAdmission.find(input.admission_id)
        phase = input.phase.to_s
        state = admission.phase_state.deep_symbolize_keys
        state[:session_id] = admission.terminal_session_id
        state[:container_id] ||= admission.runtime_id
        state[:error] = input.error if input.error.present?
        session = admission.terminal_session

        return session.strategy.on_failure(**strategy_state(state)) if phase == "on_failure"
        return cleanup(admission, session, state) if phase == "cleanup"

        # Everything here runs BEFORE any operation row exists, so a failure
        # cannot leave an unresolved operation behind.
        SessionAdmissionService.permit!(admission.id, input.permit_token)
        SessionService.revalidate_admission!(session) if REVALIDATED_PHASES.include?(phase)
        session.start! if session.may_start?

        operation = nil
        if RUNTIME_PHASES.include?(phase)
          operation = SessionAdmissionService.begin_operation!(admission.id, input.permit_token, phase)
          return operation.result.deep_symbolize_keys if operation.state == "completed"

          if phase == "create_container"
            runtime = ContainerRuntime.build
            # Identity is persisted before the create so cleanup can find the
            # object even if the answer to the create never arrives.
            admission.update!(runtime_id: runtime.session_identity(session), runtime_kind: runtime.class.name)
            state.delete(:container_id)
          end
        end

        result = ContainerService.new(strategy: session.strategy, state: strategy_state(state)).run_phase(phase)
        ActiveRecord::Base.transaction do
          operation&.update!(state: "completed", result: result)
          admission.update!(phase_state: result, runtime_id: result[:container_id] || admission.runtime_id, wait_reason: nil)
        end
        result
      rescue ContainerService::PhaseError => e
        if e.original_error.is_a?(ContainerRuntime::CapacityError)
          operation&.update!(state: "retryable", error: e.message)
          admission.update!(wait_reason: e.original_error.reason, last_error: e.message)
          return { "capacity_wait" => true }
        end
        record_failed_operation(operation, e)
        raise TemporalExceptions.non_retryable(e)
      rescue SessionAdmissionService::Stopped, SessionAdmissionService::UncertainOperation => e
        raise TemporalExceptions.non_retryable(e)
      rescue StandardError => e
        record_failed_operation(operation, e)
        raise TemporalExceptions.non_retryable(e)
      end

      private

      # `cleanup_collected` is bookkeeping for this activity's own retries; the
      # strategies take the phase state and would choke on an unknown keyword.
      def strategy_state(state) = state.except(:cleanup_collected)

      def record_failed_operation(operation, error)
        return unless operation

        cause = error.respond_to?(:original_error) ? (error.original_error || error) : error
        resolved = NEVER_DISPATCHED.any? { |klass| cause.is_a?(klass) }
        operation.update!(state: resolved ? "retryable" : "uncertain", error: "#{cause.class}: #{error.message}")
      end

      def cleanup(admission, session, state)
        SessionAdmissionService.transaction do
          admission.reload.lock!
          return state if admission.released_at
          admission.update!(stop_requested_at: admission.stop_requested_at || Time.current)
          if admission.session_runtime_operations.where(state: %w[in_flight uncertain]).exists?
            raise SessionAdmissionService::UncertainOperation, "Unresolved runtime operation: operator reconciliation required"
          end
        end

        runtime = ContainerRuntime.build
        raise "Runtime changed; operator reconciliation required" if admission.runtime_kind && admission.runtime_kind != runtime.class.name

        absent = admission.runtime_id.blank? || runtime.session_absent?(admission.runtime_id)
        unless absent
          state = collect_outputs(admission, session, state)
          runtime.cleanup_session(admission.runtime_id)
          absent = runtime.session_absent?(admission.runtime_id)
        end

        session.send(:sync_usage)
        finalize_session(session, state)

        # Deletion is asynchronous — Kubernetes accepts the DELETE long before
        # the Pod and its routing objects are gone, and an accepted request is
        # never proof of absence (AD-6). So an unfinished delete comes back as a
        # result the workflow retries on a timer, NOT as an execution failure:
        # the session already ran, and marking it failed here would be a lie.
        return state.merge(cleanup_pending: true) unless absent

        SessionAdmissionService.release!(admission)
        session.send(:notify_workflow_execution_if_step_session)
        # The slot that just came back is worth handing to whoever is waiting
        # for it; this runs in a worker, so the fan-out costs the user nothing.
        SessionLaunchRelay.drain(limit: 25)
        state
      end

      # Output collection walks the container filesystem and must not repeat on
      # a retry, so the fact that it ran is part of the durable phase state.
      def collect_outputs(admission, session, state)
        return state if state[:cleanup_collected]

        begin
          session.strategy.before_cleanup(**strategy_state(state))
        rescue StandardError => e
          state[:error] ||= "Output collection failed: #{e.message}"
        end
        state[:cleanup_collected] = true
        admission.update!(phase_state: state)
        state
      end

      # Terminal state is settled as soon as the work is over, independently of
      # how long the runtime takes to disappear. The parent workflow reads
      # "unreleased + terminal" as `finishing`, so it still waits for capacity
      # to come back before starting the next step.
      def finalize_session(session, state)
        ActiveRecord::Base.transaction do
          session.reload
          final_state = session.cancelled? ? "cancelled" : (state[:error] || session.failed? ? "failed" : "finished")
          session.update!(state: final_state, finished_at: session.finished_at || Time.current,
            container_id: nil, error_message: state[:error] || session.error_message)
        end
      end
    end
  end
end
