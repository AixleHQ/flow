# frozen_string_literal: true

module Activities
  module Workflow
    class LaunchStepSessionActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        workflow_run = step_run.workflow_run
        step = step_run.step

        agent_type = workflow_run.agent_runtime || "claude_code"
        mode = resolve_mode(workflow_run, step)

        prompt = step.instructions.presence || "Execute step: #{step.name}"

        session = TerminalSession.create!(
          user: workflow_run.user,
          project: workflow_run.project,
          session_type: "workflow_step",
          agent_type: agent_type,
          configured_agent: step.agent,
          mode: mode,
          initial_prompt: prompt,
          metadata: {
            "workflow_run_id" => workflow_run.id,
            "step_run_id" => step_run.id,
            "step_name" => step.name
          }
        )

        attach_resources!(session, step, workflow_run)
        step_run.update!(terminal_session: session)
        step_run.broadcast_update!

        session.start! if session.may_start?

        { "terminal_session_id" => session.id, "step_run_id" => step_run.id }
      end

      private

      def resolve_mode(workflow_run, step)
        auto = workflow_run.step_auto_run?(step.id)
        return "non_interactive" if auto == true
        return "non_interactive" if workflow_run.mode.non_interactive?
        return "non_interactive" if workflow_run.mode.mixed? && step.allow_non_interactive && auto != false

        "interactive"
      end

      def attach_resources!(session, step, workflow_run)
        if step.tool_ids.present?
          tools = Tool.where(id: step.tool_ids)
          session.tools << tools
        end

        if step.skill_ids.present?
          skills = Skill.where(id: step.skill_ids)
          session.skills << skills
        end

        if step.mcp_server_ids.present?
          servers = MCPServer.where(id: step.mcp_server_ids)
          session.mcp_servers << servers
        end

        if step.mount_repositories
          repo_ids = workflow_run.repository_ids.presence || workflow_run.project.repository_ids
          if repo_ids.present?
            repos = Repository.where(id: repo_ids)
            session.repositories << repos
          end
        end

        if workflow_run.input_asset_ids.present?
          assets = ::Asset.where(id: workflow_run.input_asset_ids)
          session.input_assets << assets
        end
      end
    end
  end
end
