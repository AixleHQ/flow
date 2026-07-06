# frozen_string_literal: true

require "temporalio/testing"
require "temporalio/worker"

# Runs a real Temporal workflow through the SDK time-skipping WorkflowEnvironment
# (in-memory test server — boots in ~5s once, then instant; no external deps, no
# shared Postgres). Phase 4 workflow target (docs/testing.md §2). Fake activities are
# registered on the same task queue the workflow dispatches to.
module TemporalWorkflowHelper
  # Minimal stand-in for a registry activity ref: the workflow's execute_activity
  # reads #name and #task_queue off it.
  ActivityRef = Struct.new(:name, :task_queue)

  def run_workflow(workflow_class, *args, activities: [], task_queue: "test-queue")
    env = Temporalio::Testing::WorkflowEnvironment.start_time_skipping
    worker = Temporalio::Worker.new(
      client: env.client, task_queue: task_queue,
      workflows: [ workflow_class ], activities: activities
    )
    worker.run do
      env.client.execute_workflow(
        workflow_class, *args,
        id: "test-wf-#{SecureRandom.hex(4)}", task_queue: task_queue
      )
    end
  ensure
    env&.shutdown
  end
end
