# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class CheckSkipActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @project)
        @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
      end

      def run_check_skip(step)
        run_activity(CheckSkipActivity, { "workflow_run_id" => @run.id, "step_id" => step.id })
      end

      test "skip_policy never never skips" do
        step = create(:step, workflow: @workflow, skip_policy: :never,
          output_asset_specs: [ { "name" => "report.md", "required" => true } ])
        create(:workflow_run_asset, workflow_run: @run, name: "report.md")

        result = run_check_skip(step)

        refute result["should_skip"]
        assert_nil result["reason"]
      end

      test "skip_policy manual never skips" do
        step = create(:step, workflow: @workflow, skip_policy: :manual,
          output_asset_specs: [ { "name" => "report.md", "required" => true } ])
        create(:workflow_run_asset, workflow_run: @run, name: "report.md")

        result = run_check_skip(step)

        refute result["should_skip"]
        assert_nil result["reason"]
      end

      test "if_outputs_exist skips when every required output asset is present by name" do
        step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
          output_asset_specs: [
            { "name" => "report.md", "required" => true },
            { "name" => "summary.md", "required" => true },
            { "name" => "optional.md", "required" => false }
          ])
        create(:workflow_run_asset, workflow_run: @run, name: "report.md")
        create(:workflow_run_asset, workflow_run: @run, name: "summary.md")

        result = run_check_skip(step)

        assert result["should_skip"]
        assert_equal "All required outputs already exist from previous steps", result["reason"]
      end

      test "if_outputs_exist skips when a required output matches by name_pattern" do
        step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
          output_asset_specs: [ { "name_pattern" => 'report-\d+\.md', "required" => true } ])
        create(:workflow_run_asset, workflow_run: @run, name: "report-42.md")

        result = run_check_skip(step)

        assert result["should_skip"]
        assert_equal "All required outputs already exist from previous steps", result["reason"]
      end

      test "if_outputs_exist does not skip when a required output is missing" do
        step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
          output_asset_specs: [
            { "name" => "report.md", "required" => true },
            { "name" => "summary.md", "required" => true }
          ])
        create(:workflow_run_asset, workflow_run: @run, name: "report.md")

        result = run_check_skip(step)

        refute result["should_skip"]
        assert_nil result["reason"]
      end

      test "if_outputs_exist does not skip when there are no output specs" do
        step = create(:step, workflow: @workflow, skip_policy: :if_outputs_exist,
          output_asset_specs: [])

        result = run_check_skip(step)

        refute result["should_skip"]
        assert_nil result["reason"]
      end
    end
  end
end
