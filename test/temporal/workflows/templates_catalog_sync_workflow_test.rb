# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow through the SDK time-skipping WorkflowEnvironment with a
  # fake activity registered under the real activity name (docs/testing.md §2).
  class TemplatesCatalogSyncWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "templates-catalog-sync-test"

    class FakeSyncActivity < Temporalio::Activity::Definition
      activity_name "templates_sync_catalog_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "GitHub is unreachable" if self.class.attempts < 2

        { commit_sha: "abc", upserted: 2, skipped: [], revoked: 0, unchanged: false }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:templates_sync_catalog_activity) do
        TemporalWorkflowHelper::ActivityRef.new("templates_sync_catalog_activity", TASK_QUEUE)
      end
      TemplatesCatalogSyncWorkflow.stubs(:_preloaded_activities).returns(proxy)
      FakeSyncActivity.attempts = 0
    end

    test "runs the sync activity, retrying once, and returns what it did" do
      result = run_workflow(TemplatesCatalogSyncWorkflow, activities: [ FakeSyncActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FakeSyncActivity.attempts
      assert_equal 2, result["upserted"]
    end

    test "is registered where the scheduler and the admin sync button look it up" do
      assert TemporalWorkflowRegistry.workflows["templates_catalog_sync_workflow"]
      schedule = YAML.load_file(Rails.root.join("app/temporal/schedules.yml"))["schedules"]
                     .find { |s| s["workflow"] == "templates_catalog_sync_workflow" }
      assert_equal "20 * * * *", schedule["cron"]
    end
  end
end
