# frozen_string_literal: true

# Terminal Session State Machine
# Manages lifecycle of terminal sessions (auth_setup, agent_session, tool_setup, workflow_step)
module TerminalSessionStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :not_started, initial: true
      state :started
      state :running
      state :stopped
      state :collected
      state :failed
      state :cancelled

      # Transitions
      event :start do
        transitions from: :not_started, to: :started, after: :start_temporal_workflow
      end

      event :mark_running do
        # Allow from not_started for race condition when Temporal workflow starts faster than controller commits
        transitions from: %i[not_started started], to: :running
      end

      event :stop do
        # Allow from running or collected (after auth collection, container stops)
        transitions from: %i[running collected], to: :stopped
      end

      event :collect do
        # Allow from running (auth flow) or stopped
        transitions from: %i[running stopped], to: :collected, after: :update_user_configured_agents
      end

      event :fail do
        transitions from: %i[not_started started running stopped], to: :failed, after: :cleanup_resources
      end

      event :cancel do
        transitions from: %i[not_started started running], to: :cancelled, after: :cleanup_resources
      end
    end
  end

  # Callbacks
  def start_temporal_workflow
    begin
      # Select workflow based on session type
      workflow = case session_type
                 when "auth_setup"
                   WorkflowService.workflows.agent_auth_workflow
                 when "agent_session"
                   WorkflowService.workflows.agent_session_workflow
                 else
                   raise "Unsupported session type: #{session_type}"
                 end

      result = TemporalService.start_workflow(
        workflow,
        terminal_session_id: id,
        user_id: user_id,
        agent_type: agent_type
      )

      update!(
        temporal_workflow_id: result[:workflow_id],
        temporal_run_id: result[:run_id],
        started_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("Failed to start Temporal workflow for session #{id}: #{e.message}")
      update!(error_message: "Failed to start workflow: #{e.message}")
      fail!
    end
  end

  def update_user_configured_agents
    return unless session_type == "auth_setup" && agent_type.present?

    user.add_configured_agent(agent_type) unless user.configured_agents.include?(agent_type)
    update!(collected_at: Time.current)
  end

  def cleanup_resources
    return if container_id.blank?

    # Cleanup will be handled by Temporal workflow cancellation
    # or by stop_container activity
    Rails.logger.info("Cleaning up resources for session #{id}, container: #{container_id}")
  end

  private
end
