# frozen_string_literal: true

require "test_helper"

module Workflows
  class TrackerPersonalDataWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "tracker-personal-data-test"

    class FakeRefreshActivity < Temporalio::Activity::Definition
      activity_name "trackers_report_personal_data_activity"

      def execute(_input = nil)
        { reported: 4, closed: 1, updated: 0 }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:trackers_report_personal_data_activity) do
        TemporalWorkflowHelper::ActivityRef.new("trackers_report_personal_data_activity", TASK_QUEUE)
      end
      TrackerPersonalDataWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "runs the report and returns its counts" do
      result = run_workflow(TrackerPersonalDataWorkflow, activities: [ FakeRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal [ 4, 1 ], result.values_at("reported", "closed")
    end
  end
end
