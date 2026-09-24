# frozen_string_literal: true

require "temporalio/testing"

# Runs a Temporal activity through the SDK's ActivityEnvironment — the Phase 4
# target for activity tests (docs/testing.md §2) — instead of calling #execute on
# a bare instance. ActivityEnvironment is serverless (no Temporal test server, so
# no boot/hang risk): it executes the activity inside a real activity context,
# exercising the SDK dispatch path while boundaries stay behind their fakes.
module TemporalActivityHelper
  # Runs the activity on the calling thread. The SDK's default executor hands it to
  # a process-wide thread pool whose threads outlive the test: one that leased a
  # database connection during a non-transactional test (the admission concurrency
  # tests) keeps that lease, and a later test's activity reads through it, outside
  # that test's transaction — RecordNotFound for a row the test has just created.
  class InlineActivityExecutor < Temporalio::Worker::ActivityExecutor::ThreadPool
    def execute_activity(_defn, &block)
      block.call
    end
  end

  EXECUTORS = Temporalio::Worker::ActivityExecutor.defaults.merge(default: InlineActivityExecutor.new).freeze

  def run_activity(activity, *args, **kwargs)
    Temporalio::Testing::ActivityEnvironment.new(activity_executors: EXECUTORS).run(activity, *args, **kwargs)
  end
end
