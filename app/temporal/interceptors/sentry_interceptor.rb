# frozen_string_literal: true

require "temporalio/worker/interceptor"

module Interceptors
  class SentryInterceptor
    include Temporalio::Worker::Interceptor::Activity

    def intercept_activity(next_interceptor)
      SentryActivityInbound.new(next_interceptor)
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
            Sentry.capture_exception(e) unless Temporalio::Error.canceled?(e)
            raise
          end
        end
      end
    end
  end
end
