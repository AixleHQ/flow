# frozen_string_literal: true

module Activities
  module Workflow
    class LaunchStepSessionActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        workflow_run = step_run.workflow_run
        step = step_run.step

        prompt = step.instructions.presence || "Execute step: #{step.name}"

        default_runtime = step.required_agent_runtime.presence ||
                          workflow_run.user.default_agent_runtime ||
                          "cursor_cli"

        session = TerminalSession.create!(
          user: workflow_run.user,
          project: workflow_run.project,
          session_type: "workflow_step",
          agent_type: default_runtime,
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

        config = SessionConfigResolver.resolve(session)
        session.update!(agent_type: config[:agent_runtime], mode: config[:mode])
        attach_resolved_resources!(session, config)

        step_run.broadcast_update!
        session.start! if session.may_start?

        { "terminal_session_id" => session.id, "step_run_id" => step_run.id }
      end

      private

      def attach_resolved_resources!(session, config)
        if config[:tool_ids].present?
          session.tools = Tool.where(id: config[:tool_ids])
        end

        if config[:skill_ids].present?
          session.skills = Skill.where(id: config[:skill_ids])
        end

        if config[:mcp_server_ids].present?
          session.mcp_servers = MCPServer.where(id: config[:mcp_server_ids])
        end

        if config[:repository_ids].present?
          session.repositories = Repository.where(id: config[:repository_ids])
        end

        if config[:input_asset_ids].present?
          session.input_assets = ::Asset.where(id: config[:input_asset_ids])
        end
      end
    end
  end
end
