# frozen_string_literal: true

require "test_helper"

module Interceptors
  class SentryInterceptorTest < ActiveSupport::TestCase
    # Stand-in for the rest of the interceptor chain — the collaborator the
    # SentryActivityInbound delegates to via `super`. On the success path it
    # returns a canned result. It also snapshots the live Sentry scope from
    # inside #execute so we can assert the interceptor configured the scope
    # (tags + context) before delegating.
    class RecordingInbound < Temporalio::Worker::Interceptor::Activity::Inbound
      attr_reader :received_input, :scope_tags, :temporal_context, :call_count

      def initialize(result:)
        super(nil)
        @result = result
        @call_count = 0
      end

      def execute(input)
        @call_count += 1
        @received_input = input
        scope = Sentry.get_current_scope
        @scope_tags = scope&.tags&.dup
        @temporal_context = scope&.contexts&.[]("temporal")
        @result
      end
    end

    # Minimal activity used only to obtain a real Temporalio::Activity::Context,
    # so the interceptor reads activity info the way it does in production. Its
    # body runs the interceptor against the recording inbound and returns the
    # interceptor's result. Run via `run_activity` (serverless ActivityEnvironment).
    class ProbeActivity < Temporalio::Activity::Definition
      activity_name "sentry_interceptor_probe"

      def execute(recording)
        inbound = Interceptors::SentryInterceptor.new.intercept_activity(recording)
        input = Temporalio::Worker::Interceptor::Activity::ExecuteInput.new(
          proc: -> { }, args: [], result_hint: nil, headers: {}
        )
        inbound.execute(input)
      end
    end

    class BrokenWorkflowProbe < Temporalio::Workflow::Definition
      workflow_name "sentry_interceptor_broken_probe"

      def execute
        nil.step_list_that_is_not_there
      end
    end

    class RefusingWorkflowProbe < Temporalio::Workflow::Definition
      workflow_name "sentry_interceptor_refusing_probe"

      def execute
        raise Temporalio::Error::ApplicationError.new("refused on purpose", non_retryable: true)
      end
    end

    def reported_workflow_failures
      reported = []
      Sentry.stubs(:capture_exception).with do |error, options|
        reported << [ error, options ]
        true
      end
      reported
    end

    test "an exception that would fail the workflow task is reported with the execution it wedges" do
      reported = reported_workflow_failures

      assert_raises(Temporalio::Error::WorkflowFailedError) do
        run_workflow(BrokenWorkflowProbe, interceptors: [ SentryInterceptor.new ], task_queue: "sentry-broken-probe")
      end

      error, options = reported.sole
      assert_kind_of NoMethodError, error
      assert_equal "sentry_interceptor_broken_probe", options[:tags]["temporal.workflow"]
      assert_equal "workflow_task", options[:tags]["temporal.failure"]
      assert_match(/\Atest-wf-/, options[:tags]["temporal.workflow_id"])
      assert_equal "sentry-broken-probe", options[:contexts]["temporal"][:task_queue]
    end

    test "a failure the workflow raises on purpose is its outcome, not a task failure" do
      reported = reported_workflow_failures

      assert_raises(Temporalio::Error::WorkflowFailedError) do
        run_workflow(RefusingWorkflowProbe, interceptors: [ SentryInterceptor.new ], task_queue: "sentry-refusing-probe")
      end

      assert_empty reported
    end

    test "a retried task failure is reported once per window, not once per retry" do
      failures = SentryInterceptor::WorkflowTaskFailures
      key = [ "run-#{SecureRandom.hex(4)}", "NoMethodError", "undefined method" ]

      assert failures.first_report?(key, now: 1_000)
      assert_not failures.first_report?(key, now: 1_000 + failures::REPORT_EVERY - 1)
      assert failures.first_report?(key, now: 1_000 + failures::REPORT_EVERY)
    end

    test "intercept_activity wraps the next interceptor in a SentryActivityInbound" do
      nxt = RecordingInbound.new(result: :anything)
      inbound = Interceptors::SentryInterceptor.new.intercept_activity(nxt)

      assert_instance_of Interceptors::SentryInterceptor::SentryActivityInbound, inbound
      assert_same nxt, inbound.next_interceptor
    end

    # `benign:` is the vocabulary every TemporalExceptions caller already uses for
    # an expected failure — a cleanup phase, a stop somebody asked for. Nothing
    # here honoured it, so those still became Sentry events and buried the rest.
    # Pinned against the real wrapper so the two cannot drift apart.
    test "an error its raiser labelled benign is not worth reporting" do
      inbound = Interceptors::SentryInterceptor.new.intercept_activity(RecordingInbound.new(result: nil))

      assert inbound.benign?(TemporalExceptions.non_retryable(RuntimeError.new("stopped"), benign: true))
      assert_not inbound.benign?(TemporalExceptions.non_retryable(RuntimeError.new("a real failure")))
      assert_not inbound.benign?(RuntimeError.new("never wrapped at all"))
    end

    test "execute returns the wrapped result unchanged on the success path" do
      recording = RecordingInbound.new(result: { ok: true, value: 42 })

      result = run_activity(ProbeActivity, recording)

      assert_equal({ ok: true, value: 42 }, result)
      assert_equal 1, recording.call_count
    end

    test "execute passes the ExecuteInput through to the next interceptor" do
      recording = RecordingInbound.new(result: :done)

      run_activity(ProbeActivity, recording)

      assert_instance_of Temporalio::Worker::Interceptor::Activity::ExecuteInput,
                         recording.received_input
    end

    test "execute configures the Sentry scope with activity info before delegating" do
      recording = RecordingInbound.new(result: :done)

      result = run_activity(ProbeActivity, recording)

      assert_equal :done, result

      # Tags reflect the real ActivityEnvironment default activity info; attempt
      # is stringified per the interceptor.
      tags = recording.scope_tags
      assert_not_nil tags, "expected the interceptor to expose a live Sentry scope"
      assert_equal "unknown", tags["temporal.activity"]
      assert_equal "test", tags["temporal.workflow_id"]
      assert_equal "test-run", tags["temporal.run_id"]
      assert_equal "test", tags["temporal.task_queue"]
      assert_equal "1", tags["temporal.attempt"]

      # Structured context carries the same info with native types.
      ctx = recording.temporal_context
      assert_not_nil ctx, "expected the interceptor to set the 'temporal' context"
      assert_equal "test", ctx[:activity_id]
      assert_equal "unknown", ctx[:activity_type]
      assert_equal "test", ctx[:workflow_id]
      assert_equal "test", ctx[:workflow_type]
      assert_equal "test-run", ctx[:run_id]
      assert_equal "test", ctx[:task_queue]
      assert_equal 1, ctx[:attempt]
      assert_equal "default", ctx[:namespace]
    end
  end
end
