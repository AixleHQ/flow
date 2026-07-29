# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class FireScheduleTriggerActivityTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @workflow = create(:workflow, scope: @project)
        @binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
          event_type: "schedule.fired", schedule_config: { "cron" => "* * * * *" })
      end

      test "records a schedule.fired event and starts the bound workflow" do
        WorkflowService.expects(:start).with(has_entries(workflow: @workflow, user: @user)).once.returns(build(:workflow_run))

        result = run_activity(FireScheduleTriggerActivity, Hashie::Mash.new(trigger_binding_id: @binding.id))

        assert TriggerEvent.exists?(event_type: "schedule.fired", project_id: @project.id, board_task_id: nil)
        assert result.key?(:workflow_run_id)
      end

      test "create_task subject policy makes the scheduled run create a card" do
        board = create(:board, project: @project)
        column = create(:board_column, board: board)
        @binding.update!(subject_policy: :create_task, subject_column: column, subject_title_template: "Nightly {{date}}")

        WorkflowService.expects(:start).with(has_entries(workflow: @workflow)).once.returns(build(:workflow_run))

        assert_difference -> { BoardTask.count }, 1 do
          run_activity(FireScheduleTriggerActivity, Hashie::Mash.new(trigger_binding_id: @binding.id))
        end
      end
    end
  end
end
