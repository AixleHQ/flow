# frozen_string_literal: true

# TriggerEngine is the single "brain" of the event-driven trigger layer.
#
# Every trigger source converges here instead of each one hard-coding its own
# call into WorkflowService.start:
#
#   • column auto-binding   → TaskService.check_auto_trigger → fire_for_column_binding
#   • task wait resolution  → TaskService.resolve_gate/remove_gate → check_auto_trigger
#   • manual launch button  → TaskService.trigger_workflow → fire_for_binding
#   • Slack / webhook        → Webhooks::ProcessEventJob → publish → dispatch
#
# Responsibilities:
#   1. record_event  — persist a normalized TriggerEvent (audit / replay).
#   2. dispatch      — match an event against TriggerBinding rows (Slack/webhook).
#   3. fire_*        — start a workflow once, idempotently (TriggerDispatch ledger),
#                      always through the existing WorkflowService.start.
class TriggerEngine
  class << self
    # Persist a normalized event WITHOUT dispatching. Used by the legacy internal
    # sources, which apply their own guards before deciding to fire.
    def record_event(event_type:, source:, subject: nil, data: {}, project: nil, board_task: nil, dedup_key: nil)
      TriggerEvent.create!(
        event_type: event_type,
        source: source,
        subject: subject&.to_s,
        data: data.deep_stringify_keys,
        project_id: project&.id,
        board_task_id: board_task&.id,
        dedup_key: dedup_key,
        occurred_at: Time.current
      )
    end

    # Persist a normalized event AND dispatch it to every matching TriggerBinding.
    # Used by the generic webhook / Slack ingestion path. Idempotent on dedup_key.
    def publish(event_type:, source:, subject: nil, data: {}, project: nil, board_task: nil, dedup_key: nil)
      event = record_event(
        event_type: event_type, source: source, subject: subject,
        data: data, project: project, board_task: board_task, dedup_key: dedup_key
      )
      dispatch(event)
      event
    rescue ActiveRecord::RecordNotUnique
      # Same dedup_key already ingested — already dispatched once. No-op.
      TriggerEvent.find_by(dedup_key: dedup_key)
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

      subject = resolve_subject(binding: binding, event: event, fallback_task: task)

      fire_workflow(
        workflow: binding.workflow,
        project: binding.project,
        task: subject,
        actor: actor,
        event: event,
        source: "trigger_binding:#{binding.id}",
        trigger_binding: binding
      )
    end

    # Fire the workflow bound to a legacy ColumnWorkflowBinding (auto column move
    # / wait resolution). Records the event, then fires once.
    def fire_for_column_binding(binding:, task:, actor:)
      event = record_event(
        event_type: "board.column.auto_triggered",
        source: "column_workflow_binding:#{binding.id}",
        subject: task.id,
        data: { "column_id" => binding.board_column_id, "workflow_id" => binding.workflow_id },
        project: task.board.project,
        board_task: task
      )

      fire_workflow(
        workflow: binding.workflow,
        project: task.board.project,
        task: task,
        actor: actor,
        event: event,
        source: "column_workflow_binding"
      )
    end

    # Low-level: start a workflow at most once for (event, trigger), recording a
    # TriggerDispatch ledger row. The unique dedup_key suppresses duplicates from
    # at-least-once delivery. Returns the WorkflowRun (or nil if suppressed).
    def fire_workflow(workflow:, project:, task:, actor:, event:, source:, trigger_binding: nil)
      dedup_key = dispatch_dedup_key(event, trigger_binding, source)

      dispatch = TriggerDispatch.create!(
        trigger_event: event,
        trigger_binding: trigger_binding,
        source: source,
        dedup_key: dedup_key,
        status: "matched"
      )

      run = WorkflowService.start(
        workflow: workflow,
        project: project,
        user: actor,
        task: task,
        mode: :non_interactive
      )

      dispatch.update!(
        workflow_run_id: run.try(:id),
        status: run.try(:persisted?) ? "started" : "skipped"
      )
      run
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info("[TriggerEngine] Duplicate dispatch suppressed: #{dedup_key}")
      nil
    end

    private

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
    # same event for the same binding is suppressed.
    def dispatch_dedup_key(event, trigger_binding, source)
      base = event.dedup_key.presence || "event:#{event.id}"
      target = trigger_binding ? "binding:#{trigger_binding.id}" : source
      "#{base}:#{target}"
    end
  end
end
