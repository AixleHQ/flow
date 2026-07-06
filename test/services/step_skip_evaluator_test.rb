# frozen_string_literal: true

require "test_helper"

class StepSkipEvaluatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow_run = create(:workflow_run, project: @project, user: @user)
    @workflow = @workflow_run.workflow
  end

  test "never skip_policy never skips regardless of existing outputs" do
    step = create(:step, workflow: @workflow, skip_policy: :never,
      output_asset_specs: [ { "name" => "report.md", "required" => true } ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert_not evaluator.should_skip?
    assert_nil evaluator.skip_reason
  end

  test "manual skip_policy never auto-skips even when outputs exist" do
    step = create(:step, workflow: @workflow, skip_policy: :manual,
      output_asset_specs: [ { "name" => "report.md", "required" => true } ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert_not evaluator.should_skip?
    assert_nil evaluator.skip_reason
  end

  test "if_outputs_exist skips when every required output already exists by name" do
    step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
      output_asset_specs: [
        { "name" => "report.md", "required" => true },
        { "name" => "summary.md", "required" => true }
      ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "summary.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert evaluator.should_skip?
    assert_equal "All required outputs already exist from previous steps", evaluator.skip_reason
  end

  test "if_outputs_exist skips when a name_pattern matches an existing asset" do
    step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
      output_asset_specs: [ { "name_pattern" => "^report-\\d+\\.md$", "required" => true } ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report-42.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert evaluator.should_skip?
    assert_equal "All required outputs already exist from previous steps", evaluator.skip_reason
  end

  test "if_outputs_exist ignores non-required specs when deciding to skip" do
    step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
      output_asset_specs: [
        { "name" => "report.md", "required" => true },
        { "name" => "optional.md", "required" => false }
      ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert evaluator.should_skip?
    assert_equal "All required outputs already exist from previous steps", evaluator.skip_reason
  end

  test "if_outputs_exist does not skip when a required output is missing" do
    step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
      output_asset_specs: [
        { "name" => "report.md", "required" => true },
        { "name" => "summary.md", "required" => true }
      ])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert_not evaluator.should_skip?
    assert_nil evaluator.skip_reason
  end

  test "if_outputs_exist does not skip when the step declares no output specs" do
    step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
      output_asset_specs: [])
    create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    evaluator = StepSkipEvaluator.new(step, @workflow_run)

    assert_not evaluator.should_skip?
    assert_nil evaluator.skip_reason
  end
end
