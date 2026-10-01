# frozen_string_literal: true

# Generalized "events matching X start workflow Y" rule for event sources beyond
# the two legacy ones (column moves, task gates). A binding is matched against a
# TriggerEvent by (project, event_type, enabled) plus JSONB containment of
# filter_predicate within the event data.
class TriggerBinding < ApplicationRecord
  extend Enumerize

  belongs_to :project
  belongs_to :workflow
  belongs_to :created_by, class_name: "User", optional: true
  # subject_policy = create_task → the new card is created in this column.
  belongs_to :subject_column, class_name: "BoardColumn", optional: true
  # tracker.* events only: the tracker this binding listens to; none means any
  # tracker in the project (what a migration between trackers wants).
  belongs_to :project_tracker, optional: true

  enumerize :trigger_mode, in: %i[auto manual], default: :auto, predicates: true
  # What board task (if any) a run from this trigger is about. See TriggerEngine.
  enumerize :subject_policy, in: %i[none existing_task create_task find_or_create_task],
    default: :none, predicates: { prefix: true }
  # What a tracker binding does with a change Aixle itself made
  # (docs/design/task-tracker-integrations.md §6.6).
  enumerize :aixle_changes, in: %i[ignore other_workflows always], default: :ignore

  TRACKER_EVENT_PREFIX = "tracker."
  TRACKER_SOURCE = "tracker"

  SCHEDULE_EVENT_TYPE = "schedule.fired"
  # /help is answered before any binding runs, so a trigger whose text command
  # is that word would appear in the catalog and never fire. Compare the
  # command itself (optional leading slash), not whether a looser operator
  # could also match the word.
  RESERVED_SLACK_COMMAND = /\A\/?help\z/i

  # notify_on_failure (default true) — when a run this binding started fails,
  # say so where it came from: in the Slack thread (Slack::RunFailureNotifier),
  # or, for a tracker event, as a comment on the issue, also when the run is
  # cancelled (Trackers::RunStatusReporter). A no-op on every other trigger kind.

  validates :event_type, presence: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project
  validate :create_task_requires_column
  validates :subject_column_id, tenant_ids: { model: BoardColumn, error_on: :subject_column },
                                if: -> { subject_column_id.present? && project }
  validate :schedule_requires_cron
  validate :workflow_supports_auto_run
  validate :slack_command_not_reserved
  validate :project_tracker_in_project, if: :project_tracker_id?
  validate :tracker_event_type_known, if: :tracker_event?

  scope :active, -> { where(enabled: true) }
  # Match an event to bindings. Project-scoped events (column/webhook/schedule)
  # match bindings in that project; company-scoped events (Slack — one workspace
  # serves every project of the company) fan out to bindings across all the
  # company's projects.
  scope :for_event, ->(event) {
    rel = active.where(event_type: event.event_type).joins(:workflow).merge(Workflow.active)
    # A generic webhook names its own event type, so without this a sender could
    # present itself as a tracker event.
    next none if event.event_type.to_s.start_with?(TRACKER_EVENT_PREFIX) && event.source != TRACKER_SOURCE
    if event.project_id
      rel.where(project_id: event.project_id)
    elsif event.company_id
      rel.where(project_id: Project.where(company_id: event.company_id).select(:id))
    else
      none
    end
  }

  # A schedule trigger is reconciled onto its Temporal Schedule synchronously
  # (inline, in the request) whenever it is created/updated, and removed on
  # destroy — so a scheduling failure surfaces immediately instead of being
  # silently lost by a dropped background job. The worker-boot sync
  # (ScheduleReconciler.reconcile_all) is the durable backstop. Skipped when
  # Temporal is off (e.g. test) so a save never spins up a Temporal client.
  #
  # A binding created disabled has no Temporal schedule to reconcile, so its
  # create is skipped: template installs create every trigger disabled, and
  # must not depend on Temporal being reachable.
  after_commit :reconcile_schedule, on: %i[create update], if: :schedule_needs_reconcile?
  after_commit :remove_schedule, on: :destroy, if: :reconcile_schedule?
  after_commit :ensure_tracker_event_delivery, on: %i[create update], if: -> { tracker_event? && enabled? }

  def schedule?
    event_type == SCHEDULE_EVENT_TYPE
  end

  # May this binding start its workflow right now? Off, or bound to a deleted
  # workflow, it may not — whatever still calls it (a stale schedule, a queued event).
  def live?
    enabled && workflow.present? && !workflow.deleted?
  end

  # Does the event data satisfy every condition in the predicate? Supports
  # equality (scalar values), operator objects ({"op","value"}) and dot-path
  # fields. Empty predicate ⇒ matches any event of this type. See TriggerFilter.
  def matches?(data)
    return false unless tracker_scope_matches?(data) && aixle_change_allowed?(data)

    TriggerFilter.match?(filter_predicate, data)
  end

  def tracker_event?
    event_type.to_s.start_with?(TRACKER_EVENT_PREFIX)
  end

  private

  def tracker_scope_matches?(data)
    return true unless tracker_event? && project_tracker_id

    data.to_h.dig("tracker", "id").to_i == project_tracker_id
  end

  def aixle_change_allowed?(data)
    origin = data.to_h["origin"]
    return true unless tracker_event? && origin.is_a?(Hash) && origin["aixle"]

    case aixle_changes.to_s
    when "always" then true
    when "other_workflows" then Array(origin["chain"]).map(&:to_i).exclude?(workflow_id)
    else false
    end
  end

  def project_tracker_in_project
    return if project_tracker && project_tracker.project_id == project_id && !project_tracker.detached?

    errors.add(:project_tracker, "must be an attached tracker of this project")
  end

  def ensure_tracker_event_delivery
    trackers = project_tracker ? [ project_tracker ] : ProjectTracker.usable.for_project(project)
    trackers.each { |tracker| Trackers::EnsureEventDeliveryJob.perform_later(tracker.id) }
  end

  def workflow_accessible_from_project
    return unless workflow && project

    unless Workflow.visible_for_project(project).exists?(id: workflow_id)
      errors.add(:workflow, "must be accessible from this project")
    end
  end

  def create_task_requires_column
    return unless subject_policy_create_task? || subject_policy_find_or_create_task?

    errors.add(:subject_column, "is required when subject_policy is #{subject_policy}") if subject_column_id.blank?
  end

  def tracker_event_type_known
    return if Trackers::EventPipeline::EVENT_TYPES.include?(event_type)

    errors.add(:event_type, "must be one of #{Trackers::EventPipeline::EVENT_TYPES.join(', ')}")
  end

  def schedule_requires_cron
    return unless schedule?

    errors.add(:schedule_config, "must include a cron expression") if schedule_config["cron"].blank?
  end

  def slack_command_not_reserved
    return unless event_type == "slack.message"
    return unless filter_predicate.is_a?(Hash)

    value = slack_text_command
    return if value.blank?
    return unless value.to_s.strip.match?(RESERVED_SLACK_COMMAND)

    errors.add(:filter_predicate, "can't use help — that word lists available commands")
  end

  def slack_text_command
    text = filter_predicate["text"]
    return nil if text.blank?

    text.is_a?(Hash) ? text["value"] : text
  end

  # Off-board triggers (slack / webhook / schedule) fire unattended in
  # non-interactive mode, so every step must allow auto-run — otherwise the launch
  # is silently skipped at fire time (WorkflowService#validate_mode!). Column
  # triggers are exempt by design: their manual mode puts a human on the button.
  def workflow_supports_auto_run
    return unless enabled? && workflow

    manual_steps = workflow.steps.not_deleted.reject(&:allow_non_interactive)
    return if manual_steps.empty?

    errors.add(:workflow,
      "can't run unattended — enable auto-run on these steps first: #{manual_steps.map(&:name).join(', ')}")
  end

  def reconcile_schedule?
    schedule? && TemporalService.enabled?
  end

  def schedule_needs_reconcile?
    reconcile_schedule? && !(previously_new_record? && !enabled?)
  end

  def reconcile_schedule
    ScheduleReconciler.reconcile(self)
  end

  def remove_schedule
    ScheduleReconciler.remove(id)
  end
end
