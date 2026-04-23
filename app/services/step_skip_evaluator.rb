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

  def all_outputs_satisfied?
    specs = @step.output_asset_specs
    return false if specs.blank?

    existing_names = @workflow_run.workflow_run_assets.pluck(:name)

    specs.select { |s| s["required"] }.all? do |spec|
      pattern = spec["name_pattern"]
      if pattern.present?
        regexp = Regexp.new(pattern) rescue nil
        regexp ? existing_names.any? { |name| regexp.match?(name) } : false
      else
        existing_names.include?(spec["name"])
      end
    end
  end
end
