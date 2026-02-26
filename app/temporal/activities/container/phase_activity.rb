# frozen_string_literal: true

module Activities
  module Container
    class PhaseActivity < Base
      def run(input)
        @cleanup_phase = false
        phase = input.phase.to_sym
        raw_state = input.state || input.context || {}
        state = raw_state.is_a?(Hash) ? {}.merge(raw_state).deep_symbolize_keys : {}
        state[:session_id] ||= input.session_id.to_i if input.respond_to?(:session_id) && input.session_id
        state[:error] = input.error if input.respond_to?(:error) && input.error.present?

        @cleanup_phase = phase == :cleanup

        strategy = resolve_strategy(input)
        service = ContainerService.new(strategy: strategy, state: state)

        log(:info, "[ContainerPhase] #{phase} for #{strategy.class.name.demodulize}")
        service.run_phase(phase)
      rescue ContainerService::PhaseError, ArgumentError => e
        raise TemporalExceptions.non_retryable(e, benign: @cleanup_phase)
      rescue Docker::Error::NotFoundError => e
        raise TemporalExceptions.non_retryable(e, benign: @cleanup_phase)
      rescue Docker::Error::DockerError => e
        raise TemporalExceptions.wrap(e, retryable: true)
      end

      private

      def resolve_strategy(input)
        if input.tool_id.present?
          tool = Tool.find(input.tool_id)
          project = input.project_id.present? ? Project.find(input.project_id) : nil

          tool.send(:build_strategy,
            parameters: input.parameters || {},
            project: project,
            session: nil,
            timeout: input.timeout,
            tool_result_id: input.respond_to?(:tool_result_id) ? input.tool_result_id : nil
          )
        elsif input.session_id.present?
          session = TerminalSession.find(input.session_id)

          if input.error.present?
            strategy = session.strategy
            return strategy
          end

          session.strategy
        else
          raise ArgumentError, "Cannot resolve strategy: need session_id or tool_id"
        end
      end
    end
  end
end
