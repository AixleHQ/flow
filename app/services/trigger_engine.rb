# frozen_string_literal: true

# TriggerEngine is the single "brain" of the event-driven trigger layer.
#
# Every trigger source converges here instead of each one hard-coding its own
# call into WorkflowService.start:
#
#   • column auto-binding   → TaskService.check_auto_trigger → record_column_trigger → dispatch_pending
#   • task gate resolution  → TaskService.resolve_gate/remove_gate → record_column_trigger → dispatch_pending
#   • manual launch button  → TaskService.trigger_workflow → record_event + dispatch_pending
#   • Slack / webhook        → Webhooks::ProcessEventJob → publish (record + dispatch_pending)
#   • schedule              → FireScheduleTriggerActivity → record_event + fire_for_binding
#
# Transactional outbox: internal producers record a "pending" TriggerEvent INSIDE
# the same DB transaction as their domain write, then dispatch it inline (the
# happy path). If the process dies after the commit but before/while dispatching,
# the event is left "pending" and OutboxRelay (a Temporal cron) sweeps it later
# and dispatches it. Double-firing is prevented by the TriggerDispatch unique
# dedup_key, which is stable per (event, target) across inline + relay retries.
#
# Responsibilities:
#   1. record_event   — persist a normalized TriggerEvent (audit / replay / outbox).
#   2. dispatch_pending — route a recorded event to its target(s) once, then mark it
#                         dispatched; the single entry point shared by the inline
#                         path and the relay.
#   3. fire_*         — start a workflow once, idempotently (TriggerDispatch ledger),
#                       always through the existing WorkflowService.start.
class TriggerEngine
  # event_type → how dispatch_pending routes it.
  COLUMN_EVENT_TYPE = "board.column.auto_triggered"
  MANUAL_EVENT_TYPE = "workflow.manual_requested"

  class << self
    # Persist a normalized event WITHOUT dispatching.
    #
    # relay_state: "pending" enrols the event in the outbox (the relay will sweep
    # it if it is never dispatched). "dispatched" records an inert audit row that
    # the relay ignores — used by paths that dispatch through another durable
    # mechanism (e.g. the schedule activity, which Temporal already retries).
    def record_event(event_type:, source:, subject: nil, data: {}, project: nil, board_task: nil,
                     actor: nil, dedup_key: nil, relay_state: "pending")
      TriggerEvent.create!(
        event_type: event_type,
        source: source,
        subject: subject&.to_s,
        data: data.deep_stringify_keys,
        project_id: project&.id,
        board_task_id: board_task&.id,
        actor_id: actor&.id,
        dedup_key: dedup_key,
        relay_state: relay_state,
        occurred_at: Time.current
      )
    end

    # Persist a normalized event AND dispatch it. Used by the generic webhook /
    # Slack ingestion path. Idempotent on dedup_key: a redelivered event is
    # recorded once and dispatched once.
    def publish(event_type:, source:, subject: nil, data: {}, project: nil, board_task: nil, dedup_key: nil)
      event = record_event(
        event_type: event_type, source: source, subject: subject,
        data: data, project: project, board_task: board_task, dedup_key: dedup_key,
        relay_state: "pending"
      )
      dispatch_pending(event)
      event
    rescue ActiveRecord::RecordNotUnique
      # Same dedup_key already ingested — already recorded (and dispatched) once.
      TriggerEvent.find_by(dedup_key: dedup_key)
    end

    # Route a recorded "pending" event to its target(s) exactly once, then mark it
    # dispatched. Shared by the inline producer path (called right after the
    # producer's transaction commits) and OutboxRelay (crash recovery). Idempotent:
    # safe to call more than once for the same event — TriggerDispatch dedup
    # suppresses any duplicate workflow launch. Returns the array of WorkflowRuns.
    def dispatch_pending(event)
      return [] if event.nil?

      # Atomically claim the event so only one of the inline path / relay routes it.
      # Accepts a stuck "dispatching" row (a router that died mid-flight, which the
      # relay re-sweeps past the grace window); route_pending stays idempotent via
      # the TriggerDispatch dedup_key, so a re-route never double-launches.
      claimed = TriggerEvent
        .where(id: event.id, relay_state: %w[pending dispatching])
        .update_all(relay_state: "dispatching", updated_at: Time.current)
      return [] unless claimed == 1

      event.reload
      runs = route_pending(event)
      event.update!(relay_state: "dispatched", dispatched_at: Time.current)
      Array(runs).compact
    rescue StandardError => e
      attempts = event.relay_attempts.to_i + 1
      next_state = attempts >= TriggerEvent::RELAY_MAX_ATTEMPTS ? "failed" : "pending"
      event.update_columns(
        relay_state: next_state, relay_attempts: attempts,
        relay_error: e.message.to_s.truncate(250), updated_at: Time.current
      )
      Rails.logger.error("[TriggerEngine] dispatch_pending failed for event ##{event.id} (attempt #{attempts}): #{e.message}")
      []
    end

    # Match an event against the generalized binding registry and fire each.
    # Returns the array of created workflow runs (nils for suppressed duplicates).
    def dispatch(event)
      return [] if event.project_id.blank?

      TriggerBinding.for_event(event).select { |b| b.matches?(event.data) }.map do |binding|
        fire_for_binding(binding: binding, event: event, task: event.board_task, actor: binding.created_by)
      end
    end

    # Fire the workflow bound to a TriggerBinding (Slack/webhook/custom source).
    # The binding's subject_policy decides what board task (if any) the run is
    # about: none → task-less project run; existing_task → the event's task;
    # create_task → a fresh card in the binding's subject_column.
    def fire_for_binding(binding:, event:, task: nil, actor: nil)
      actor ||= binding.created_by
      return nil if actor.nil? # a run requires a user

      # Resolve the subject (which may CREATE a card for subject_policy:create_task)
      # inside fire_workflow's dispatch lock, so a re-dispatch of the same event
      # never creates a duplicate card or a second run.
      fire_workflow(
        workflow: binding.workflow,
        project: binding.project,
        actor: actor,
        event: event,
        source: "trigger_binding:#{binding.id}",
        trigger_binding: binding
      ) { resolve_subject(binding: binding, event: event, fallback_task: task) }
    end

    # Record a pending column auto-trigger event (no dispatch). Called INSIDE the
    # producer's transaction so the event commits atomically with the task move /
    # gate change. The caller dispatches it (inline) after the transaction commits.
    def record_column_trigger(binding:, task:, actor:)
      record_event(
        event_type: COLUMN_EVENT_TYPE,
        source: "column_workflow_binding:#{binding.id}",
        subject: task.id,
        data: { "column_id" => binding.board_column_id, "workflow_id" => binding.workflow_id },
        project: task.board.project,
        board_task: task,
        actor: actor,
        relay_state: "pending"
      )
    end

    # Records a column auto-trigger event and dispatches it immediately. Retained
    # as a convenience entry point (and for callers that want the synchronous run).
    def fire_for_column_binding(binding:, task:, actor:)
      event = record_column_trigger(binding: binding, task: task, actor: actor)
      dispatch_pending(event).first
    end

    # Low-level: start a workflow at most once for (event, target), recording a
    # TriggerDispatch ledger row whose unique dedup_key suppresses duplicates from
    # at-least-once delivery and relay retries.
    #
    # The launch runs under dispatch.with_lock so two concurrent callers for the
    # same (event, target) serialize: the loser re-reads the row and sees the run.
    # It also RESUMES a dispatch left in "matched" with no run — the state a crash
    # between the ledger insert and WorkflowService.start leaves behind — so the
    # relay finishes the launch instead of suppressing it forever. The subject is
    # resolved inside the lock (via the block) so a re-dispatch never creates a
    # second card. Returns the WorkflowRun (or nil if suppressed / skipped).
    #
    # NOTE: delivery is still at-least-once — a crash after WorkflowService.start
    # succeeds at Temporal but before the row commits can re-execute the workflow
    # (the Temporal id is per-WorkflowRun, not per dedup_key). Consumers must be
    # idempotent.
    def fire_workflow(workflow:, project:, actor:, event:, source:, trigger_binding: nil, task: nil)
      dedup_key = dispatch_dedup_key(event, trigger_binding, source)

      dispatch = find_or_create_dispatch(
        event: event, trigger_binding: trigger_binding, source: source, dedup_key: dedup_key
      )

      result = nil
      dispatch.with_lock do
        if dispatch.workflow_run_id.present?
          result = dispatch.workflow_run            # already started → idempotent no-op
        elsif dispatch.status == "skipped"
          result = nil                              # a prior attempt decided not to start
        else
          subject = block_given? ? yield : task     # resolve (and maybe create) inside the lock
          result = WorkflowService.start(
            workflow: workflow, project: project, user: actor,
            task: subject, mode: :non_interactive
          )
          dispatch.update!(
            workflow_run_id: result.try(:id),
            status: result.try(:persisted?) ? "started" : "skipped"
          )
        end
      end
      result
    end

    private

    # Route a pending event to its dispatch target by type. Column/manual events
    # carry the launch intent (workflow_id + actor) and are fired directly; every
    # other source is matched against the binding registry.
    def route_pending(event)
      case event.event_type
      when COLUMN_EVENT_TYPE then fire_recorded_launch(event, source: "column_workflow_binding")
      when MANUAL_EVENT_TYPE then fire_recorded_launch(event, source: "manual")
      else dispatch(event)
      end
    end

    # Fire a workflow from an event that recorded its own launch intent (column
    # auto-trigger / manual button). The decision to fire was already made when the
    # event was recorded (guards applied in TaskService); the relay simply finishes
    # the launch the recorded intent describes.
    def fire_recorded_launch(event, source:)
      workflow = Workflow.find_by(id: event.data["workflow_id"])
      task = event.board_task
      actor = event.actor
      return [] if workflow.nil? || task.nil? || actor.nil?

      [ fire_workflow(
        workflow: workflow, project: event.project, task: task,
        actor: actor, event: event, source: source
      ) ].compact
    end

    def find_or_create_dispatch(event:, trigger_binding:, source:, dedup_key:)
      TriggerDispatch.create!(
        trigger_event: event,
        trigger_binding: trigger_binding,
        source: source,
        dedup_key: dedup_key,
        status: "matched"
      )
    rescue ActiveRecord::RecordNotUnique
      TriggerDispatch.find_by!(dedup_key: dedup_key)
    end

    # Resolve the board task a binding's run should be about, per subject_policy.
    def resolve_subject(binding:, event:, fallback_task:)
      case binding.subject_policy.to_s
      when "existing_task" then event.board_task || fallback_task
      when "create_task"   then create_subject_task(binding, event)
      else nil # none → task-less, project-level run
      end
    end

    def create_subject_task(binding, event)
      column = binding.subject_column
      return nil if column.nil?

      # Create directly (not via TaskService) so we don't re-enter check_auto_trigger.
      column.board.board_tasks.create!(
        board_column: column,
        title: render_title(binding.subject_title_template, event)
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[TriggerEngine] create_task failed for binding ##{binding.id}: #{e.message}")
      nil
    end

    # Minimal title templating: {{date}} and {{<top-level event.data key>}}.
    def render_title(template, event)
      tpl = template.presence || "#{event.event_type} — {{date}}"
      tpl.gsub(/\{\{\s*([\w.]+)\s*\}\}/) do
        key = Regexp.last_match(1)
        key == "date" ? (event.occurred_at || Time.current).to_date.to_s : event.data[key].to_s
      end.strip.presence || event.event_type
    end

    # Internal events carry no external dedup_key → key on the event id so a
    # dispatch is always unique (never suppresses an expected launch). External
    # events carry a stable dedup_key (e.g. Slack event_id) → re-delivery of the
    # same event for the same binding is suppressed. Stable across inline + relay
    # retries for the same event, which is what makes re-dispatch safe.
    def dispatch_dedup_key(event, trigger_binding, source)
      base = event.dedup_key.presence || "event:#{event.id}"
      target = trigger_binding ? "binding:#{trigger_binding.id}" : source
      "#{base}:#{target}"
    end
  end
end
