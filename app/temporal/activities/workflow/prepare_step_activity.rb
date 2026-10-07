# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])

        references = check_references(step_run)
        return fail_step(step_run, "Reference check failed", references) if references.any?

        validation = validate_inputs(step_run)
        return fail_step(step_run, "Input validation failed", validation.errors) unless validation.valid?

        step_run.mark_running!
        step_run.create_sub_step_runs!

        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id
        }
      end

      private

      def fail_step(step_run, label, errors)
        step_run.mark_failed!("#{label}: #{errors.join(', ')}")
        {
          "step_run_id" => step_run.id,
          "step_id" => step_run.step_id,
          "workflow_run_id" => step_run.workflow_run_id,
          "failed" => true,
          "validation_errors" => errors
        }
      end

      # A reference the agent would read as "[missing reference]" fails the step
      # here, before a session is spent on it.
      def check_references(step_run)
        return [] if InstructionReferences.scan(step_run.step.instructions).empty?

        workflow_run = step_run.workflow_run
        DataFlow::Check.for_workflow(step_run.step.workflow, project: workflow_run.project,
                                                             run_input_asset_ids: workflow_run.input_asset_ids)
                       .errors
                       .select { |issue| issue.step_key == step_run.step_id.to_s && issue.code.in?(DataFlow::Check::REFERENCE_CODES) }
                       .map(&:message)
      rescue StandardError => e
        Rails.logger.error("[PrepareStepActivity] Reference check crashed: #{e.class}: #{e.message}")
        [ "reference check could not run: #{e.message}" ]
      end

      # A validator that crashed has not judged the step's inputs, so the step does
      # not start on them — the same rule CompleteStepActivity#validate_outputs keeps.
      def validate_inputs(step_run)
        step = step_run.step
        workflow_run = step_run.workflow_run

        available = collect_available_input_names(step, workflow_run)
        InputValidator.new(step, available).validate!
      rescue StandardError => e
        Rails.logger.error("[PrepareStepActivity] Input validation crashed: #{e.class}: #{e.message}")
        InputValidator::Result.new(valid?: false, errors: [ "input validation could not run: #{e.message}" ])
      end

      # Outputs of every step this one runs after, directly or not — what
      # WorkflowStepStrategy#inject_prior_step_outputs copies in — and the active
      # assets SessionConfigResolver#resolve_input_asset_ids mounts, by name and by
      # their folder path.
      def collect_available_input_names(step, workflow_run)
        names = []

        upstream_ids = step.upstream_step_ids
        if upstream_ids.present?
          names += workflow_run.workflow_run_assets
            .joins("JOIN step_runs ON step_runs.id = workflow_run_assets.produced_by_step_run_id")
            .where(step_runs: { step_id: upstream_ids })
            .pluck(:name)
        end

        injected_asset_ids = (step.workflow&.base_asset_ids || []) +
                             (step.asset_ids || []) +
                             (workflow_run.input_asset_ids || [])
        if injected_asset_ids.present?
          names += ::Asset.accessible_from_project(workflow_run.project).where(id: injected_asset_ids.uniq)
                          .flat_map { |asset| [ asset.name, asset.picker_name ] }
        end

        names.uniq
      end
    end
  end
end
