# frozen_string_literal: true

# Base class for container-related Temporal activities
# Provides strategy resolution, session/container lookup, and error handling
#
# Subclasses implement `run(input)` and use helper methods:
#   - resolve_strategy_class(type)
#   - build_strategy(type, session_or_input)
#   - find_session(id)
#   - find_container(id)

module Activities
  class ContainerActivityBase < Base
    STRATEGY_MAP = {
      "tool_execution" => ContainerStrategies::ToolExecutionStrategy,
      "agent_auth" => ContainerStrategies::AgentAuthStrategy,
      "agent_session" => ContainerStrategies::AgentSessionStrategy
    }.freeze

    protected

    # Resolve strategy class by type string or symbol
    def resolve_strategy_class(strategy_type)
      type_key = strategy_type.to_s
      STRATEGY_MAP.fetch(type_key) do
        raise ArgumentError, "Unknown strategy type: #{strategy_type}"
      end
    end

    # Build strategy instance from session
    def build_strategy_from_session(strategy_type, session)
      return nil unless session

      strategy_class = resolve_strategy_class(strategy_type)
      strategy_class.new(
        user_id: session.user_id,
        agent_type: session.agent_type,
        session_id: session.id,
        route_token: session.route_token
      )
    end

    # Build strategy instance from raw input (for execute)
    def build_strategy_from_input(strategy_type, strategy_input)
      strategy_class = resolve_strategy_class(strategy_type)
      prepared = prepare_strategy_input(strategy_type, strategy_input)
      strategy_class.new(**prepared)
    end

    # Find session by ID (returns nil if not found)
    def find_session(session_id)
      return nil if session_id.blank?

      TerminalSession.find_by(id: session_id)
    end

    # Find Docker container by ID (returns nil if not found)
    def find_container(container_id)
      return nil if container_id.blank?

      Docker::Container.get(container_id)
    rescue Docker::Error::NotFoundError
      nil
    end

    # Update session after successful container start
    def mark_session_running(session_id, container_id)
      return unless session_id.present? && container_id.present?

      session = find_session(session_id)
      return unless session

      session.update!(container_id: container_id)
      session.mark_running! if session.may_mark_running?
      log(:info, "Session #{session_id} marked running")
    rescue StandardError => e
      log(:warn, "Failed to mark session running: #{e.message}")
    end

    # Update session after cleanup
    def mark_session_collected(session_id, cleanup_status)
      session = find_session(session_id)
      return unless session

      case cleanup_status
      when :cleaned_up, :force_removed
        session.update(container_id: nil)
        session.collect! if session.may_collect?
      when :not_found
        session.update(container_id: nil)
      end

      log(:info, "Session #{session_id} collected")
    rescue StandardError => e
      log(:warn, "Failed to update session: #{e.message}")
    end

    private

    # Prepare input hash for strategy initialization
    def prepare_strategy_input(strategy_type, input)
      case strategy_type.to_s
      when "tool_execution"
        {
          tool: Tool.find(input[:tool_id]),
          parameters: input[:parameters] || {},
          project: input[:project_id] ? Project.find(input[:project_id]) : nil,
          timeout: input[:timeout]
        }
      when "agent_auth"
        input.slice(:user_id, :agent_type, :session_id, :route_token).symbolize_keys
      when "agent_session"
        input.slice(:user_id, :agent_type, :session_id, :route_token).symbolize_keys.merge(
          credential: input[:credential_id] ? AgentCredential.find(input[:credential_id]) : nil
        )
      else
        input.symbolize_keys
      end
    end
  end
end
