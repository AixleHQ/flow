# frozen_string_literal: true

module Activities
  module Container
    class AdmittedPhaseActivity < Base
      def run(input)
        admission = SessionAdmission.find(input.admission_id)
        phase = input.phase.to_s
        state = admission.phase_state.deep_symbolize_keys
        state[:session_id] = admission.terminal_session_id
        state[:container_id] ||= admission.runtime_id
        state[:error] = input.error if input.error.present?
        session = admission.terminal_session

        if phase == "on_failure"
          return session.strategy.on_failure(**state)
        end
        if phase == "cleanup"
          return cleanup(admission, session, state)
        end
        SessionAdmissionService.transaction { SessionAdmissionService.permit!(admission.id, input.permit_token) }
        SessionService.revalidate_admission!(session) if %w[pull_image create_container exec].include?(phase)
        session.start! if session.may_start?
        if %w[create_container start_container exec].include?(phase)
          operation = SessionAdmissionService.begin_operation!(admission.id, input.permit_token, phase)
          return operation.result if operation.state == "completed"
          if phase == "create_container"
            runtime = ContainerRuntime.build
            admission.update!(runtime_id: runtime.session_identity(session), runtime_kind: runtime.class.name)
            state.delete(:container_id)
          end
        end
        result = ContainerService.new(strategy: session.strategy, state: state).run_phase(phase)
        SessionAdmissionService.transaction do
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
        operation&.update!(state: "uncertain", error: e.message)
        raise TemporalExceptions.non_retryable(e)
      rescue SessionAdmissionService::Stopped, SessionAdmissionService::UncertainOperation => e
        raise TemporalExceptions.non_retryable(e)
      rescue StandardError => e
        operation&.update!(state: "uncertain", error: e.message)
        raise TemporalExceptions.non_retryable(e)
      end

      private

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
        if admission.runtime_id && !runtime.session_absent?(admission.runtime_id)
          begin
            session.strategy.before_cleanup(**state)
          rescue StandardError => e
            state[:error] ||= "Output collection failed: #{e.message}"
          end
          runtime.cleanup_session(admission.runtime_id)
          raise "Runtime cleanup pending" unless runtime.session_absent?(admission.runtime_id)
        end
        session.send(:sync_usage)
        SessionAdmissionService.transaction do
          return state if admission.reload.released_at
          session.reload
          final_state = session.cancelled? ? "cancelled" : (state[:error] || session.failed? ? "failed" : "finished")
          session.update!(state: final_state, finished_at: session.finished_at || Time.current,
            container_id: nil, error_message: state[:error] || session.error_message)
          SessionAdmissionService.release!(admission)
        end
        session.send(:notify_workflow_execution_if_step_session)
        state
      end
    end
  end
end
