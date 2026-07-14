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

  enumerize :trigger_mode, in: %i[auto manual], default: :auto, predicates: true
  # What board task (if any) a run from this trigger is about. See TriggerEngine.
  enumerize :subject_policy, in: %i[none existing_task create_task],
    default: :none, predicates: { prefix: true }

  SCHEDULE_EVENT_TYPE = "schedule.fired"

  validates :event_type, presence: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project
  validate :create_task_requires_column
  validate :schedule_requires_cron
  validate :workflow_supports_auto_run

  scope :active, -> { where(enabled: true) }
  # Match an event to bindings. Project-scoped events (column/webhook/schedule)
  # match bindings in that project; company-scoped events (Slack — one workspace
  # serves every project of the company) fan out to bindings across all the
  # company's projects.
  scope :for_event, ->(event) {
    rel = active.where(event_type: event.event_type)
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
  after_commit :reconcile_schedule, on: %i[create update], if: :reconcile_schedule?
  after_commit :remove_schedule, on: :destroy, if: :reconcile_schedule?

  def schedule?
    event_type == SCHEDULE_EVENT_TYPE
  end

  # Does the event data satisfy every condition in the predicate? Supports
  # equality (scalar values), operator objects ({"op","value"}) and dot-path
  # fields. Empty predicate ⇒ matches any event of this type. See TriggerFilter.
  def matches?(data)
    TriggerFilter.match?(filter_predicate, data)
  end

  private

  def workflow_accessible_from_project
    return unless workflow && project

    unless Workflow.visible_for_project(project).exists?(id: workflow_id)
      errors.add(:workflow, "must be accessible from this project")
    end
  end

  def create_task_requires_column
    return unless subject_policy_create_task?

    errors.add(:subject_column, "is required when subject_policy is create_task") if subject_column_id.blank?
  end

  def schedule_requires_cron
    return unless schedule?

    errors.add(:schedule_config, "must include a cron expression") if schedule_config["cron"].blank?
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

  def reconcile_schedule
    ScheduleReconciler.reconcile(self)
  end

  def remove_schedule
    ScheduleReconciler.remove(id)
  end
end
