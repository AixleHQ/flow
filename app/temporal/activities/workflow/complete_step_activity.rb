# frozen_string_literal: true

module Activities
  module Workflow
    class CompleteStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        session = step_run.terminal_session

        if session&.state == "failed"
          step_run.mark_failed!(session.error_message.presence || "Session failed")
          return { "step_run_id" => step_run.id, "valid" => false, "failed" => true }
        end

        assets = collected_assets(step_run)
        validation = validate_outputs(step_run, assets)

        unless validation.valid?
          step_run.mark_failed!("Output validation failed: #{validation.errors.join(', ')}")
          return {
            "step_run_id" => step_run.id,
            "validation_errors" => validation.errors,
            "valid" => false,
            "failed" => true
          }
        end

        step_run.mark_completed!

        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id,
          "assets_collected" => assets.size,
          "valid" => true
        }
      end

      private

      def collected_assets(step_run)
        step_run.produced_workflow_run_assets.reload.to_a
      end

      def validate_outputs(step_run, assets)
        OutputValidator.new(step_run.step, assets).validate!
      rescue StandardError => e
        Rails.logger.error("[CompleteStepActivity] Output validation failed: #{e.message}")
        OutputValidator::Result.new(valid?: true, errors: [])
      end
    end
  end
end
