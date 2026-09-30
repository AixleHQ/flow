# frozen_string_literal: true

module InternalTools
  module Concerns
    # Target resolution, write guarding and the operation ledger shared by every
    # tracker_* tool. Provider specifics stay behind Trackers::Provider.
    module TrackerContext
      extend ActiveSupport::Concern

      TRACKER_PARAM = "Tracker handle from tracker_list. Optional: defaults to the tracker that started this run, " \
                      "then to the tracker an issue URL belongs to, then to the project's primary tracker."
      ISSUE_PARAM = "The issue: its id, key or browser URL."
      OPERATION_KEY_PARAM = "Optional idempotency key. Reusing it for the same request replays the first result " \
                            "instead of writing twice; an identical retry in this session is recognised without one."

      private

      def tracker_guard
        yield
      rescue Trackers::Error => e
        error(e.to_h.to_json)
      rescue TrackerOperation::Conflict => e
        error({ error: "conflict", message: e.message }.to_json)
      end

      def resolve_tracker!(ref: params[:issue])
        Trackers::TargetResolver.new(project: project, workflow_run: workflow_run)
                                .resolve!(requested: params[:tracker], ref: ref)
      end

      def writable_tracker!(ref: params[:issue])
        tracker = resolve_tracker!(ref: ref)
        return tracker if tracker.read_write?

        primary = ProjectTracker.for_project(project).find_by(primary: true)
        hint = primary && primary != tracker ? " — the primary tracker is '#{primary.handle}'" : ""
        raise Trackers::Error.new("Tracker '#{tracker.handle}' is read-only#{hint}", code: "read_only")
      end

      def respond(value)
        success(value.as_json.to_json)
      end

      # Claims the ledger row before the provider call, so a retry is recognised
      # and the tracker event the write causes can be attributed to this run.
      # A failed claim may be retried — the provider refused it, nothing was
      # written — but an unknown one may not.
      def with_write(tracker, operation, payload, change: {})
        key = params[:operation_key].presence || automatic_key(operation, payload)
        record, state = TrackerOperation.claim!(project_tracker: tracker, key: key, operation: operation,
                                                payload: payload, change: change, **run_attribution)
        return replayed(record) if state == :replayed && !record.failed?

        record.update!(state: :pending, error_code: nil) if record.failed?
        value = yield
        record.succeed!(value, result_ref: value.id)
        record.update!(issue_id: value.is_a?(Trackers::Comment) ? value.issue_id : value.id)
        success(value.as_json.merge("operation_key" => key).to_json)
      rescue Trackers::Error::OutcomeUnknown => e
        record&.unknown!
        error({ error: "outcome_unknown", operation_key: key,
                message: "#{e.message}. The request may have been applied — read the issue before retrying; " \
                         "reissuing it can create a duplicate." }.to_json)
      rescue Trackers::Error => e
        record&.fail!(e.code)
        error(e.to_h.merge(operation_key: key).to_json)
      end

      def automatic_key(operation, payload)
        "auto-" + Digest::SHA256.hexdigest([ session&.id, operation, TrackerOperation.digest_for(payload) ].join(":"))[0, 40]
      end

      def run_attribution
        {
          terminal_session_id: session&.id, user_id: session&.user_id,
          workflow_run_id: workflow_run&.id, workflow_id: workflow_run&.workflow_id,
          chain: Array(workflow_run&.shared_context.to_h.dig("tracker", "chain"))
        }
      end

      def replayed(record)
        case record.state.to_s
        when "succeeded"
          success(record.result.merge("operation_key" => record.operation_key, "replayed" => true).to_json)
        when "unknown"
          error({ error: "outcome_unknown", operation_key: record.operation_key,
                  message: "This request was sent earlier and never confirmed. Read the issue before retrying." }.to_json)
        else
          error({ error: "operation_in_flight", operation_key: record.operation_key,
                  message: "This request is still being processed." }.to_json)
        end
      end

      # A task-scoped run that files or touches an issue records which issue the
      # task is about, so Task Details and later triggers can find it.
      def link_run_task(tracker, issue)
        task = workflow_run&.board_task
        return unless task

        link_task(task, tracker, issue)
      end

      def link_task(task, tracker, issue)
        provider = tracker.tracker_provider
        ExternalResource.find_or_create_by!(
          board_task: task, kind: ExternalResource::TRACKER_ISSUE, provider: tracker.provider,
          instance: provider.instance, external_id: issue.id.to_s
        ) do |link|
          link.data = { "key" => issue.key, "url" => issue.url, "project_tracker_id" => tracker.id }.compact
        end
      end
    end
  end
end
