# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        step_run.mark_running!
        step_run.create_sub_step_runs!

        prepare_workspace(step_run)

        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id
        }
      end

      private

      def prepare_workspace(step_run)
        return unless step_run.terminal_session&.container_id.present?

        preparator = WorkspacePreparator.new(step_run)
        preparator.prepare!(step_run.terminal_session.container_id)
      rescue StandardError => e
        Temporalio::Activity.logger.warn("[PrepareStepActivity] Workspace preparation failed: #{e.message}")
      end
    end
  end
end
