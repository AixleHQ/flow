# frozen_string_literal: true

class StepSkipEvaluator
  def initialize(step, workflow_run)
    @step = step
    @workflow_run = workflow_run
  end

  def should_skip?
    case @step.skip_policy.to_s
    when "never"
      false
    when "if_outputs_exist"
      all_outputs_satisfied?
    when "manual"
      false
    else
      false
    end
  end

  def skip_reason
    return nil unless should_skip?

    "All required outputs already exist from previous steps"
  end

  private

  # Nothing required to look for is not "everything already exists": a step
  # whose outputs are all optional runs.
  def all_outputs_satisfied?
    required = @step.output_specs.select { |spec| spec.required? && !spec.blank? }
    return false if required.empty?

    existing_names = @workflow_run.workflow_run_assets.pluck(:name)
    required.all? { |spec| existing_names.any? { |name| spec.matches?(name) } }
  end
end
