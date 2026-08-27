# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepListActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        steps = workflow_run.workflow.steps.not_deleted.order(:position)
        overrides = workflow_run.step_overrides || {}
        # Latest, not first: a resumed run's retried step has a newer pending
        # step_run alongside the original failed one, and the workflow must
        # pick up the fresh attempt. Grouped once up front, not per step, to
        # avoid an N+1 (this fires on every workflow execution start/resume).
        step_runs_by_step_id = workflow_run.step_runs.order(:created_at).group_by(&:step_id)
        failed_counts_by_step_id = workflow_run.step_runs.where(state: :failed).group(:step_id).count

        steps.map do |step|
          existing_run = step_runs_by_step_id[step.id]&.last
          step_override = overrides[step.id.to_s] || {}
          auto_run = step_override.key?("auto_run") ? step_override["auto_run"] : step.allow_non_interactive

          {
            "step_id" => step.id,
            "step_run_id" => existing_run&.id,
            "step_run_state" => existing_run&.state,
            "failed_attempt_count" => failed_counts_by_step_id[step.id] || 0,
            "position" => step.position,
            "auto_run" => auto_run,
            "depends_on_step_ids" => step.depends_on_step_ids || [],
            "on_failure" => step.on_failure.to_s,
            "max_retries" => step.max_retries.to_i,
            "skip_policy" => step.skip_policy.to_s
          }
        end
      end
    end
  end
end
