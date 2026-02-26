# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])

        validation = validate_inputs(step_run)
        unless validation.valid?
          step_run.mark_failed!("Input validation failed: #{validation.errors.join(', ')}")
          return {
            "step_run_id" => step_run.id,
            "step_id" => step_run.step_id,
            "workflow_run_id" => step_run.workflow_run_id,
            "failed" => true,
            "validation_errors" => validation.errors
          }
        end

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

      def validate_inputs(step_run)
        step = step_run.step
        workflow_run = step_run.workflow_run

        available = collect_available_input_names(step, workflow_run)
        InputValidator.new(step, available).validate!
      rescue StandardError => e
        Rails.logger.error("[PrepareStepActivity] Input validation error: #{e.message}")
        InputValidator::Result.new(valid?: true, errors: [])
      end

      def collect_available_input_names(step, workflow_run)
        names = []

        dep_ids = step.depends_on_step_ids
        if dep_ids.present?
          names += workflow_run.workflow_run_assets
            .joins("JOIN step_runs ON step_runs.id = workflow_run_assets.produced_by_step_run_id")
            .where(step_runs: { step_id: dep_ids })
            .pluck(:name)
        end

        if workflow_run.input_asset_ids.present?
          names += ::Asset.where(id: workflow_run.input_asset_ids).pluck(:name)
        end

        names.uniq
      end

      def prepare_workspace(step_run)
        return unless step_run.terminal_session&.container_id.present?

        preparator = WorkspacePreparator.new(step_run)
        preparator.prepare!(step_run.terminal_session.container_id)
      rescue StandardError => e
        Rails.logger.warn("[PrepareStepActivity] Workspace preparation failed: #{e.message}")
      end
    end
  end
end
