# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class PrepareStepActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @company)
        @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
        @activity = PrepareStepActivity.new

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      test "a step asset satisfies a required input_asset_spec" do
        asset = create(:asset, scope: @project, created_by: @user, name: "brief.md")
        step = create(:step, workflow: @workflow,
          input_asset_specs: [ { "name" => "brief.md", "required" => true } ],
          asset_ids: [ asset.id ])
        step_run = create(:step_run, workflow_run: @run, step: step)

        result = @activity.execute({ "step_run_id" => step_run.id })

        refute result["failed"]
        assert_equal "running", step_run.reload.state
      end

      test "a workflow base asset satisfies a required input_asset_spec" do
        asset = create(:asset, scope: @project, created_by: @user, name: "style_guide.md")
        @workflow.merge_config!(base_asset_ids: [ asset.id ])
        step = create(:step, workflow: @workflow,
          input_asset_specs: [ { "name" => "style_guide.md", "required" => true } ])
        step_run = create(:step_run, workflow_run: @run, step: step)

        result = @activity.execute({ "step_run_id" => step_run.id })

        refute result["failed"]
      end

      test "a missing required input_asset_spec fails validation" do
        step = create(:step, workflow: @workflow,
          input_asset_specs: [ { "name" => "nowhere.md", "required" => true } ])
        step_run = create(:step_run, workflow_run: @run, step: step)

        result = @activity.execute({ "step_run_id" => step_run.id })

        assert result["failed"]
        assert_includes result["validation_errors"].join, "nowhere.md"
        assert_equal "failed", step_run.reload.state
      end
    end
  end
end
