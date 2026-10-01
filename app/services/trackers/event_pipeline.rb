# frozen_string_literal: true

module Trackers
  # One provider notification → normalized tracker.* events, published into
  # every Aixle project that maps the external project in
  # (docs/design/task-tracker-integrations.md §6).
  #
  # The issue is re-read through the provider, so what triggers match and what
  # an agent is shown is the tracker's current state. Changes made by Aixle are
  # attributed to the run that made them (§6.6), and the hard limits stop a
  # chain of Aixle-caused events whatever the bindings say.
  class EventPipeline
    EVENT_TYPES = %w[
      tracker.issue.created tracker.issue.status_changed tracker.issue.assigned tracker.comment.created
    ].freeze
    TEXT_LIMIT = 500
    MAX_CHAIN_DEPTH = 5
    ISSUE_BUDGET = 10
    ATTRIBUTION_WINDOW = 10.minutes

    def initialize(integration)
      @integration = integration
      @provider = Provider.for(integration)
    end

    def process(notification)
      trackers = ProjectTracker.usable.where(integration: @integration, external_scope_id: notification.scope_id)
                               .includes(:project).to_a
      return [] if trackers.empty? || !awaited?(trackers)

      issue = @provider.get_issue(notification.scope_id, notification.issue_id)
      events = derive(notification, issue)
      return [] if events.empty?

      origin = origin_for(notification, issue, events)
      TrackerAccount.remember!(provider: @integration.provider, account_ids: @provider.account_ids(notification))
      trackers.flat_map do |tracker|
        next [] if over_limits?(tracker, issue, origin)

        events.map { |event_type, extra| publish(tracker, event_type, notification, issue, origin, extra) }
      end
    end

    private

    def awaited?(trackers)
      TriggerBinding.active.where(project_id: trackers.map(&:project_id), event_type: EVENT_TYPES).exists?
    end

    # [[event_type, extra data]]; an update can mean a status change and an
    # assignment at once.
    def derive(notification, issue)
      case notification.kind
      when :issue_created then [ [ "tracker.issue.created", {} ] ]
      when :comment_created then [ [ "tracker.comment.created", { "comment" => comment_data(notification) } ] ]
      when :issue_updated
        status = @provider.status_change(notification.changes, issue)
        assignee = notification.changes.find { |c| c[:field] == "assignee" }
        [
          (status && [ "tracker.issue.status_changed", { "change" => status } ]),
          (assignee && [ "tracker.issue.assigned", { "change" => assignee.transform_keys(&:to_s).merge("field" => "assignee") } ])
        ].compact
      else []
      end
    end

    def comment_data(notification)
      text = notification.comment_text.to_s
      {
        "id" => notification.comment_id, "author" => notification.actor[:name],
        "mentions_me" => @provider.mentions_self?(text), "text" => bounded(ActionView::Base.full_sanitizer.sanitize(text))
      }.compact
    end

    # Which run caused this change, if Aixle did. Matched against the write
    # ledger of every tracker on this external project, since the run that wrote
    # may belong to another Aixle project than the one observing the change.
    def origin_for(notification, issue, events)
      operation = matching_operation(notification, issue, events)
      if operation
        chain = Array(operation.chain) + [ operation.workflow_id ].compact
        return { "aixle" => true, "attributed" => true, "workflow_run_id" => operation.workflow_run_id,
                 "workflow_id" => operation.workflow_id, "chain" => chain, "depth" => chain.size }
      end
      return unless @provider.own_actor?(notification.actor)

      { "aixle" => true, "attributed" => false, "chain" => [], "depth" => 1 }
    end

    def matching_operation(notification, issue, events)
      recent = TrackerOperation.joins(:project_tracker)
                               .where(project_trackers: { integration_id: @integration.id, external_scope_id: notification.scope_id })
                               .where(issue_id: issue.id, state: %w[pending succeeded])
                               .where(created_at: ATTRIBUTION_WINDOW.ago..)
                               .order(created_at: :desc)
      case notification.kind
      when :issue_created then recent.find_by(operation: "create_issue")
      when :comment_created then recent.find_by(operation: "add_comment")
      when :issue_updated
        change = events.find { |type, _| type == "tracker.issue.status_changed" }&.dig(1, "change").to_h
        # A transition sets the state; on Azure the event names the column the card moved to.
        targets = [ change.dig("to", "name"), change.dig("state", "to") ].compact_blank
        by_status = targets.any? && recent.where(operation: "transition_issue").detect do |op|
          targets.any? { |target| op.change["to"].to_s.casecmp?(target) }
        end
        assigned = events.any? { |type, _| type == "tracker.issue.assigned" }
        by_status || (assigned ? recent.find_by(operation: "assign_issue") : nil)
      end
    end

    def over_limits?(tracker, issue, origin)
      return false unless origin

      if origin["depth"].to_i >= MAX_CHAIN_DEPTH
        skip(tracker, issue, "chain_depth_limit")
      elsif recent_aixle_events(tracker, issue) >= ISSUE_BUDGET
        skip(tracker, issue, "issue_chain_budget")
      else
        false
      end
    end

    def recent_aixle_events(tracker, issue)
      TriggerEvent.where(project_id: tracker.project_id, source: "tracker", created_at: 1.hour.ago..)
                  .where("data -> 'issue' ->> 'id' = ? AND data -> 'origin' ->> 'aixle' = 'true'", issue.id)
                  .where("data -> 'tracker' ->> 'id' = ?", tracker.id.to_s)
                  .count
    end

    def skip(tracker, issue, reason)
      Rails.logger.warn("[Trackers::EventPipeline] #{reason}: tracker #{tracker.id} issue #{issue.id} — not published")
      true
    end

    def publish(tracker, event_type, notification, issue, origin, extra)
      data = {
        "tracker" => { "id" => tracker.id, "handle" => tracker.handle, "provider" => tracker.provider },
        "issue" => issue_data(issue),
        "actor" => notification.actor.transform_keys(&:to_s).merge("is_me" => origin.present?),
        "origin" => origin,
        "text" => event_text(event_type, issue, extra),
        "external_resource" => {
          "provider" => tracker.provider, "instance" => @provider.instance, "external_id" => issue.id,
          "key" => issue.key, "url" => issue.url
        }.compact
      }.merge(extra).compact

      TriggerEngine.publish(
        event_type: event_type, source: "tracker", subject: "#{tracker.provider}:#{issue.id}",
        project: tracker.project, data: data,
        dedup_key: dedup_key(tracker, event_type, issue, notification)
      )
    end

    def issue_data(issue)
      {
        "id" => issue.id, "key" => issue.key, "url" => issue.url, "title" => issue.title, "type" => issue.type,
        "status" => issue.status&.as_json&.slice("name", "category")&.compact, "assignees" => issue.assignees,
        "labels" => issue.labels
      }.compact
    end

    def event_text(event_type, issue, extra)
      return extra.dig("comment", "text") if event_type == "tracker.comment.created"

      bounded([ issue.title, ActionView::Base.full_sanitizer.sanitize(issue.description.to_s) ].compact_blank.join("\n\n"))
    end

    # Keyed by the external identity, not by the delivery: two connections to the
    # same Azure project, mapped into one Aixle project, still fire once.
    def dedup_key(tracker, event_type, issue, notification)
      discriminator = notification.comment_id || notification.revision || notification.occurred_at
      Digest::SHA256.hexdigest(
        [ tracker.project_id, tracker.provider, @provider.instance, issue.id, event_type, discriminator ].join(":")
      )
    end

    def bounded(text)
      text.to_s.truncate(TEXT_LIMIT, omission: "… [truncated]")
    end
  end
end
