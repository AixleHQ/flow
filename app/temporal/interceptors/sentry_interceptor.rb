# frozen_string_literal: true

require "temporalio/worker/interceptor"

module Interceptors
  class SentryInterceptor
    include Temporalio::Worker::Interceptor::Activity
    include Temporalio::Worker::Interceptor::Workflow

    def intercept_activity(next_interceptor)
      SentryActivityInbound.new(next_interceptor)
    end

    def intercept_workflow(next_interceptor)
      SentryWorkflowInbound.new(next_interceptor)
    end

    class SentryActivityInbound < Temporalio::Worker::Interceptor::Activity::Inbound
      def execute(input)
        activity_context = Temporalio::Activity::Context.current
        info = activity_context.info

        Sentry.with_scope do |scope|
          scope.set_tags(
            "temporal.activity" => info.activity_type,
            "temporal.workflow_id" => info.workflow_id,
            "temporal.run_id" => info.workflow_run_id,
            "temporal.task_queue" => info.task_queue,
            "temporal.attempt" => info.attempt.to_s
          )
          scope.set_context("temporal", {
            activity_id: info.activity_id,
            activity_type: info.activity_type,
            workflow_id: info.workflow_id,
            workflow_type: info.workflow_type,
            run_id: info.workflow_run_id,
            task_queue: info.task_queue,
            attempt: info.attempt,
            namespace: info.workflow_namespace
          })

          begin
            super
          rescue StandardError => e
            # Activity cancellations (tab closed, workflow cancelled by the user)
            # are expected control flow, not application errors — don't report
            # them to Sentry. Still re-raise so Temporal handles the cancellation.
            Sentry.capture_exception(e) unless Temporalio::Error.canceled?(e) || benign?(e)
            raise
          end
        end
      end

      # `benign:` already means "an expected error" everywhere TemporalExceptions
      # is raised — cleanup phases, deliberate stops — and the SDK carries it as
      # the error's category. Nothing honoured it here, so every failure a caller
      # had deliberately labelled expected still became a Sentry event.
      #
      # respond_to? rather than a bare call: the category reader is the SDK's, and
      # a silent NoMethodError inside an error handler would swallow the error it
      # was handling.
      def benign?(error)
        error.is_a?(Temporalio::Error::ApplicationError) &&
          error.respond_to?(:category) &&
          error.category == TemporalExceptions::BENIGN
      end
    end

    # An exception out of workflow code that is not a Temporal failure fails the
    # workflow *task*, not the workflow: the server retries the task forever and
    # the execution sits suspended until a deploy fixes it. The SDK reports it
    # only as a WARN log line, so a broken deploy wedges every execution it
    # touches and nothing alerts.
    class SentryWorkflowInbound < Temporalio::Worker::Interceptor::Workflow::Inbound
      def execute(input)
        super
      rescue StandardError => e
        WorkflowTaskFailures.report(e)
        raise
      end

      def handle_signal(input)
        super
      rescue StandardError => e
        WorkflowTaskFailures.report(e, signal: input.signal)
        raise
      end
    end

    module WorkflowTaskFailures
      # Each retry of the task raises again, on whichever worker picks it up.
      REPORT_EVERY = 3600

      @reported = {}
      @mutex = Mutex.new

      class << self
        def report(error, signal: nil)
          return unless task_failure?(error)

          info = Temporalio::Workflow.info
          # Outside the deterministic scheduler: reporting is I/O, and it must
          # not become part of the workflow's history.
          Temporalio::Workflow::Unsafe.durable_scheduler_disabled do
            next unless first_report?([ info.run_id, error.class.name, error.message ])

            Sentry.capture_exception(error,
              tags: { "temporal.workflow" => info.workflow_type, "temporal.workflow_id" => info.workflow_id,
                      "temporal.run_id" => info.run_id, "temporal.task_queue" => info.task_queue,
                      "temporal.failure" => "workflow_task" },
              contexts: { "temporal" => { workflow_type: info.workflow_type, workflow_id: info.workflow_id,
                                          run_id: info.run_id, task_queue: info.task_queue,
                                          namespace: info.namespace, signal: signal&.to_s }.compact })
          end
        rescue StandardError => e
          Rails.logger.error("[Temporal] Could not report a workflow task failure: #{e.class}: #{e.message}")
        end

        def task_failure?(error)
          !(error.is_a?(Temporalio::Error::Failure) || error.is_a?(Timeout::Error) ||
            error.is_a?(Temporalio::Workflow::ContinueAsNewError) || Temporalio::Error.canceled?(error))
        end

        def first_report?(key, now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
          @mutex.synchronize do
            @reported.delete_if { |_, at| now - at >= REPORT_EVERY }
            next false if @reported.key?(key)

            @reported[key] = now
            true
          end
        end
      end
    end
  end
end
