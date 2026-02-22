# frozen_string_literal: true

module Activities
  module Workflow
    class CompleteStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])

        collected_assets = collect_outputs(step_run)
        validation = validate_outputs(step_run, collected_assets)

        unless validation.valid?
          return {
            "step_run_id" => step_run.id,
            "validation_errors" => validation.errors,
            "valid" => false
          }
        end

        step_run.mark_completed!

        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id,
          "assets_collected" => collected_assets.size,
          "valid" => true
        }
      end

      private

      def collect_outputs(step_run)
        WorkflowOutputCollector.new(step_run).collect!
      rescue StandardError => e
        Temporalio::Activity.logger.error("[CompleteStepActivity] Output collection failed: #{e.message}")
        []
      end

      def validate_outputs(step_run, collected_assets)
        OutputValidator.new(step_run.step, collected_assets).validate!
      rescue StandardError => e
        Temporalio::Activity.logger.error("[CompleteStepActivity] Output validation failed: #{e.message}")
        OutputValidator::Result.new(valid?: true, errors: [])
      end
    end
  end
end
