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

    # A create names its issue only once the tracker answers, and the tracker's
    # event can arrive first. Such an event is retried — WRITE_RETRY_ATTEMPTS
    # runs, WRITE_RETRY_WAIT apart — while a create on its project is still
    # waiting for an answer. A create pending for longer than CREATE_IN_FLIGHT
    # (a few requests at their read timeouts) is a crashed one, not in flight.
    WRITE_RETRY_WAIT = 5.seconds
    WRITE_RETRY_ATTEMPTS = 12
    CREATE_IN_FLIGHT = 2.minutes

    # Raised instead of publishing an event a create still in flight may have caused.
    class WriteInFlight < StandardError; end

    # Whether any trigger waits for this connection's events — what a receiver
    # checks before it records a delivery from a provider that sends everything.
    def self.awaited_by?(integration)
      projects = ProjectTracker.usable.where(integration: integration).select(:project_id)
      TriggerBinding.active.where(project_id: projects, event_type: EVENT_TYPES).exists?
    end

    # `wait_for_writes: false` publishes such an event as it stands: the caller's
    # last attempt.
    def initialize(integration, wait_for_writes: false)
      @integration = integration
      @provider = Provider.for(integration)
      @wait_for_writes = wait_for_writes
    end

    def process(notification)
      trackers = ProjectTracker.usable.where(integration: @integration, external_scope_id: notification.scope_id)
                               .includes(:project).to_a
      return [] if trackers.empty? || !awaited?(trackers)

      issue = @provider.get_issue(notification.scope_id, notification.issue_id)
      notification = confirmed(notification, issue)
      return [] unless notification

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

    def confirmed(notification, issue)
      @provider.confirm(notification, issue).tap do |result|
        unless result
          Rails.logger.info("[Trackers::EventPipeline] unconfirmed_change: integration #{@integration.id} " \
                            "issue #{issue.id} #{notification.kind} — not published")
        end
      end
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
        "mentions_me" => @provider.mentions_self?(Trackers.without_code(text)),
        "text" => bounded(ActionView::Base.full_sanitizer.sanitize(text))
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
      if @wait_for_writes && create_in_flight?(notification)
        raise WriteInFlight, "a create in #{notification.scope_id} has not been answered yet"
      end
      return unless @provider.own_actor?(notification.actor)

      { "aixle" => true, "attributed" => false, "chain" => [], "depth" => 1 }
    end

    def ledger(notification)
      TrackerOperation.joins(:project_tracker)
                      .where(project_trackers: { integration_id: @integration.id, external_scope_id: notification.scope_id })
    end

    def create_in_flight?(notification)
      notification.kind == :issue_created &&
        ledger(notification).where(operation: "create_issue", state: "pending", issue_id: nil)
                            .where(created_at: CREATE_IN_FLIGHT.ago..).exists?
    end

    # A write still in flight recorded the issue as its caller named it, which
    # on Jira may be the key rather than the id.
    def matching_operation(notification, issue, events)
      recent = ledger(notification).where(issue_id: [ issue.id, issue.key ].compact_blank.uniq, state: %w[pending succeeded])
                                   .where(created_at: ATTRIBUTION_WINDOW.ago..)
                                   .order(created_at: :desc)
      case notification.kind
      when :issue_created then recent.find_by(operation: "create_issue")
      when :comment_created then comment_operation(recent, notification)
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

    # When the provider names the comment, it is Aixle's only if the ledger
    # names it too, or if a write is still unanswered and the comment's author
    # is not known to be someone else. A person's comment right after one of
    # Aixle's is theirs. A provider that names no comment keeps the recent write.
    def comment_operation(recent, notification)
      writes = recent.where(operation: "add_comment")
      return writes.first if notification.comment_id.blank?

      writes.find_by(result_ref: notification.comment_id.to_s) ||
        (writes.find_by(result_ref: nil) unless someone_else?(notification.actor))
    end

    def someone_else?(actor)
      @provider.identity.present? && actor.present? && !@provider.own_actor?(actor)
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
