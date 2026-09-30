# frozen_string_literal: true

module Trackers
  # What TriggerEngine does differently for an event the tracker pipeline
  # published: the run's tracker context, and finding or creating the board task
  # an issue is about (docs/design/task-tracker-integrations.md §6.4, §7.5).
  #
  # Only events whose source is the pipeline qualify. A generic webhook chooses
  # its own event type and data, and must not reach any of this.
  module TriggerSupport
    DEFAULT_TITLE = "{{issue.key}} {{issue.title}}"

    module_function

    def event?(event)
      event.source == TriggerBinding::TRACKER_SOURCE && event.data.to_h["tracker"].is_a?(Hash)
    end

    def run_context(event)
      return {} unless event?(event)

      data = event.data
      chain = Array(data.dig("origin", "chain"))
      {
        "tracker" => {
          "project_tracker_id" => data.dig("tracker", "id"), "handle" => data.dig("tracker", "handle"),
          "provider" => data.dig("tracker", "provider"), "event_type" => event.event_type,
          "issue" => data["issue"].to_h.slice("id", "key", "url", "title", "type", "status"),
          "change" => data["change"], "comment" => data["comment"].to_h.slice("id", "author", "text").presence,
          "chain" => chain, "depth" => chain.size
        }.compact
      }
    end

    # The active task in the binding's project linked to the event's issue. A
    # link its own workflow made wins, then the oldest; several links from other
    # workflows is ambiguous, and no task is better than the wrong one.
    def linked_task(binding, event)
      links = links_for(binding, event).to_a
      same_workflow = links.select { |link| link.data["workflow_id"].to_s == binding.workflow_id.to_s }
      return same_workflow.first.board_task if same_workflow.any?
      return links.first.board_task if links.one?

      if links.many?
        Rails.logger.info("[Trackers::TriggerSupport] ambiguous_external_subject binding #{binding.id} event #{event.id}")
      end
      nil
    end

    # `issue.created` and `status_changed` for one issue dispatch under different
    # TriggerDispatch locks, so without this both could create a task.
    def find_or_create_task(binding, event)
      lock!(binding, event)
      linked_task(binding, event) || yield
    end

    def link!(task, binding, event)
      identity = event.data["external_resource"].to_h
      return if task.nil? || identity["external_id"].blank?

      ExternalResource.find_or_create_by!(
        board_task: task, kind: ExternalResource::TRACKER_ISSUE, provider: identity["provider"],
        instance: identity["instance"], external_id: identity["external_id"]
      ) do |link|
        link.data = { "key" => identity["key"], "url" => identity["url"], "workflow_id" => binding.workflow_id,
                      "binding_id" => binding.id, "project_tracker_id" => event.data.dig("tracker", "id") }.compact
      end
    end

    def task_body(event)
      issue = event.data["issue"].to_h
      [ issue["url"] && "From #{issue['key'] || issue['id']}: #{issue['url']}", event.data["text"].presence ]
        .compact.join("\n\n").presence
    end

    def links_for(binding, event)
      identity = event.data["external_resource"].to_h
      ExternalResource.identifying(provider: identity["provider"], instance: identity["instance"],
                                   external_id: identity["external_id"])
                      .joins(board_task: :board).where(boards: { project_id: binding.project_id })
                      .merge(BoardTask.active).includes(:board_task).order(:created_at, :id)
    end

    def lock!(binding, event)
      identity = event.data["external_resource"].to_h
      key = [ binding.project_id, identity["provider"], identity["instance"], identity["external_id"] ].join(":")
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", key ])
      )
    end
  end
end
