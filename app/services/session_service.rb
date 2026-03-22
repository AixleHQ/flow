# frozen_string_literal: true

class SessionService
  class << self
    def create_and_start(user:, project: nil, session_type:, agent_type: nil, configured_agent: nil, params: {})
      session = user.terminal_sessions.build(
        project: project,
        session_type: session_type,
        agent_type: agent_type,
        configured_agent: configured_agent,
        **params.slice(:mode, :initial_prompt, :metadata, :session_config,
                       :tool_ids, :skill_ids, :mcp_server_ids, :input_asset_ids, :repository_ids)
      )

      return session unless session.save

      session.start! if session.may_start?
      start_temporal_workflow(session)

      session
    end

    def finish(session:)
      raise TerminalSession::InvalidStateError, "Cannot finish session in state: #{session.state}" unless session.may_finish?

      signal_container_finished(session) if session.temporal_workflow_id.present?
    end

    def cancel(session:)
      cancel_temporal_workflow(session) if session.temporal_workflow_id.present?
      session.fail! if session.may_fail?
    end

    def create_for_workflow_step(step_run:)
      workflow_run = step_run.workflow_run
      step = step_run.step

      prompt = step.instructions.presence || "Execute step: #{step.name}"
      runtime = step.required_agent_runtime.presence ||
                workflow_run.agent_runtime.presence ||
                workflow_run.user.default_agent_runtime.presence ||
                workflow_run.user.agent_credentials.order(created_at: :desc).first&.agent_type ||
                "cursor_cli"

      session = TerminalSession.create!(
        user: workflow_run.user,
        project: workflow_run.project,
        session_type: "workflow_step",
        agent_type: runtime,
        configured_agent: step.agent,
        mode: "interactive",
        initial_prompt: prompt,
        metadata: {
          "workflow_run_id" => workflow_run.id,
          "step_run_id" => step_run.id,
          "step_name" => step.name
        }
      )

      step_run.update!(terminal_session: session)
      # Notify workflow run subscribers as soon as the step is linked, so the UI can open
      # TerminalSessionChannel before resolver / Temporal (which can take a long time).
      step_run.broadcast_update!

      config = SessionConfigResolver.resolve(session)
      session.update!(agent_type: config[:agent_runtime], mode: config[:mode])
      attach_resolved_resources(session, config)
      session.start! if session.may_start?
      start_temporal_workflow(session)

      session
    end

    private

    def start_temporal_workflow(session)
      result = TemporalService.start_workflow(
        TemporalWorkflowRegistry.container_workflow,
        { session_id: session.id, manifest: session.strategy.build_manifest },
        id: session.workflow_id,
        execution_timeout: TerminalSession::WORKFLOW_TIMEOUT
      )
      raise result[:error] unless result[:ok]

      session.update!(
        temporal_workflow_id: result[:workflow_id],
        temporal_run_id: result[:run_id]
      )
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to start workflow for session #{session.id}: #{e.message}")
      session.update!(error_message: "Failed to start workflow: #{e.message}")
      session.fail! if session.may_fail?
    end

    def signal_container_finished(session)
      # Signal the container workflow to stop. For workflow_step sessions, the execution
      # workflow is notified by WorkflowStepStrategy#before_cleanup *after* outputs are
      # collected, to avoid a race with CompleteStepActivity output validation.
      TemporalService.send_signal(session.workflow_id, :container_finished, session.step_run&.id)
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to signal container_finished for session #{session.id}: #{e.message}")
    end

    def cancel_temporal_workflow(session)
      TemporalService.cancel_workflow(session.workflow_id)
    rescue StandardError => e
      Rails.logger.error("[SessionService] Failed to cancel workflow for session #{session.id}: #{e.message}")
    end

    def attach_resolved_resources(session, config)
      session.tools = scoped_resources(Tool, config[:tool_ids], session) if config[:tool_ids].present?
      session.skills = scoped_resources(Skill, config[:skill_ids], session) if config[:skill_ids].present?
      session.mcp_servers = scoped_resources(MCPServer, config[:mcp_server_ids], session) if config[:mcp_server_ids].present?
      session.repositories = scoped_resources(Repository, config[:repository_ids], session) if config[:repository_ids].present?
      session.input_assets = scoped_resources(Asset, config[:input_asset_ids], session) if config[:input_asset_ids].present?
    end

    def scoped_resources(klass, ids, session)
      base = if session.project
               klass.visible_for_project(session.project)
      else
               klass.visible_for_company(session.user.company)
      end
      base.where(id: ids)
    end
  end
end
