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
  # What a run this trigger started tells the place it came from: nothing, that
  # it failed (a comment on the issue, a message in the thread), or — chat
  # only — a status card that follows the run (docs/design/teams-integration.md §8.2).
  enumerize :status_reporting, in: %i[none failures lifecycle], default: :failures

  TRACKER_EVENT_PREFIX = "tracker."
  TRACKER_SOURCE = "tracker"

  WEBHOOK_EVENT_PREFIX = "webhook."
  SCHEDULE_EVENT_TYPE = "schedule.fired"
  SLACK_EVENT_TYPE = "slack.message"
  # notify_on_failure is the boolean status_reporting replaces; the two are kept
  # in step until nothing reads it any more.

  validates :event_type, presence: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project
  validate :create_task_requires_column
  validates :subject_column_id, tenant_ids: { model: BoardColumn, error_on: :subject_column },
                                if: -> { subject_column_id.present? && project }
  validate :schedule_requires_cron
  validate :workflow_supports_auto_run
  validate :chat_command_not_reserved
  validate :chat_provider_named, if: -> { event_type == Chat::EVENT_TYPE }
  validates :status_reporting, inclusion: { in: %w[none failures], message: "lifecycle is for chat triggers" },
                               unless: :chat?
  before_validation :keep_failure_reporting_in_step
  before_validation :normalize_chat_trigger
  validate :project_tracker_in_project, if: :project_tracker_id?
  validate :tracker_event_type_known, if: :tracker_event?
  validate :tracker_binding_not_duplicated, if: -> {
    tracker_event? && (new_record? || will_save_change_to_filter_predicate? || will_save_change_to_project_tracker_id?)
  }

  scope :active, -> { where(enabled: true) }
  # Match an event to bindings. Project-scoped events (column/webhook/schedule)
  # match bindings in that project; company-scoped events (chat — one workspace
  # serves every project of the company) fan out to bindings across all the
  # company's projects.
  scope :for_event, ->(event) {
    chat = Chat.provider_for(event)
    # A generic webhook names its own event type, so without this a sender could
    # present itself as a tracker or chat event.
    next none if event.event_type.to_s.start_with?(TRACKER_EVENT_PREFIX) && event.source != TRACKER_SOURCE
    next none if Chat.event?(event) && chat.nil?

    rel = active.where(event_type: chat ? Chat.event_types_for(chat) : event.event_type)
                .joins(:workflow).merge(Workflow.active)
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
  # A webhook trigger's endpoint is found by its event type, not by a key, so
  # nothing else turns it off: removing the trigger would leave its URL live.
  after_destroy_commit :disable_webhook_endpoint, if: :webhook?

  def schedule?
    event_type == SCHEDULE_EVENT_TYPE
  end

  def self.chat_not_connected(label)
    "#{label} is not connected for this company. Connect it on the Integrations page first — " \
      "until then no message can reach this trigger."
  end

  def chat?
    Chat.event_types.include?(event_type)
  end

  # The messenger a chat trigger listens to: named by a legacy event type, or
  # by the `provider` condition every `chat.message` trigger carries.
  def chat_provider
    return nil unless chat?

    Chat::LEGACY_EVENT_TYPES[event_type] || filter_predicate.to_h["provider"].presence
  end

  # Points a `chat.message` trigger at another messenger, keeping its other conditions.
  # A channel id means nothing to another messenger, so it is dropped.
  def assign_chat_provider(key)
    return if key.blank? || !chat?

    filter = filter_predicate.to_h
    filter = filter.except("channel") if chat_provider.present? && chat_provider != key.to_s
    self.filter_predicate = filter.merge("provider" => key.to_s)
  end

  # save! for a person creating or editing a trigger: refuses to create or switch
  # on a chat trigger while the company has not connected its messenger. Not a
  # validation, so a workspace disconnected later does not make every other save
  # of the triggers it served fail.
  def save_checking_chat!
    normalize_chat_trigger
    if chat? && enabled? && (new_record? || enabled_changed? || chat_provider_changed?) && !chat_connected?
      valid? # report the binding's other problems alongside this one
      errors.add(:base, self.class.chat_not_connected(Chat.provider(chat_provider)&.label || "The messenger"))
      raise ActiveRecord::RecordInvalid, self
    end

    save!
  end

  # May this binding start its workflow right now? Off, or bound to a deleted
  # workflow, it may not — whatever still calls it (a stale schedule, a queued event).
  def live?
    enabled && workflow.present? && !workflow.deleted?
  end

  # Does the event data satisfy every condition in the predicate? Supports
  # equality (scalar values), operator objects ({"op","value"}) and dot-path
  # fields. Empty predicate ⇒ matches any event of this type. See TriggerFilter.
  # A chat message's text compares without regard to case: people type
  # "Deploy" and "deploy" for the same command.
  def matches?(data)
    return false unless tracker_scope_matches?(data) && aixle_change_allowed?(data)

    TriggerFilter.match?(filter_predicate, data, ignore_case: chat? ? %w[text] : [])
  end

  def webhook?
    event_type.to_s.start_with?(WEBHOOK_EVENT_PREFIX)
  end

  def tracker_event?
    event_type.to_s.start_with?(TRACKER_EVENT_PREFIX)
  end

  private

  def disable_webhook_endpoint
    return if TriggerBinding.where(project_id: project_id, event_type: event_type).exists?

    WebhookEndpoint.where(project_id: project_id).where("config ->> 'event_type' = ?", event_type)
                   .update_all(enabled: false, updated_at: Time.current)
  end

  def normalize_chat_trigger
    move_legacy_chat_trigger
    keep_chat_provider if persisted? && event_type == Chat::EVENT_TYPE
  end

  # A trigger saved as `slack.message` that is pointed at another messenger
  # becomes a `chat.message` one, the only type that messenger's messages reach.
  def move_legacy_chat_trigger
    legacy = Chat::LEGACY_EVENT_TYPES[event_type]
    named = filter_predicate.to_h["provider"]
    self.event_type = Chat::EVENT_TYPE if legacy && named.present? && named != legacy
  end

  def chat_provider_changed?
    return false if new_record?

    was = Chat::LEGACY_EVENT_TYPES[event_type_was] || filter_predicate_was.to_h["provider"]
    was.to_s != chat_provider.to_s
  end

  def chat_connected?
    chat_provider.present? && Integration.active.exists?(provider: chat_provider, company_id: project&.company_id)
  end

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

  # A binding keeps the tracker it names through a detach, so it stays editable
  # without being widened to any tracker; it just cannot be moved onto one.
  def project_tracker_in_project
    return if project_tracker && project_tracker.project_id == project_id &&
              (!project_tracker.detached? || !will_save_change_to_project_tracker_id?)

    errors.add(:project_tracker, "must be an attached tracker of this project")
  end

  # Every binding a tracker event matches starts its own run, so a copy would
  # start the workflow twice per event.
  def tracker_binding_not_duplicated
    copies = TriggerBinding.where(project_id: project_id, workflow_id: workflow_id, event_type: event_type,
                                  project_tracker_id: project_tracker_id)
                           .where("filter_predicate = ?::jsonb", filter_predicate.to_json)
    copies = copies.where.not(id: id) if persisted?
    return unless copies.exists?

    errors.add(:workflow, "already has a trigger for this tracker event with the same conditions")
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

  # Help is answered before any binding runs, so a trigger whose text command
  # is that word would appear in the catalog and never fire. Compare the
  # command itself (optional leading slash), not whether a looser operator
  # could also match the word.
  def chat_command_not_reserved
    return unless chat?
    return unless filter_predicate.is_a?(Hash)

    value = chat_text_command
    return if value.blank?
    return unless value.to_s.strip.match?(Chat::RESERVED_COMMAND)

    errors.add(:filter_predicate, "can't use help — that word lists available commands")
  end

  # Replacing a chat trigger's conditions keeps the messenger it listens to;
  # moving it to another one is assign_chat_provider.
  def keep_chat_provider
    previous = filter_predicate_was.to_h["provider"]
    return if previous.blank? || filter_predicate.to_h.key?("provider")

    self.filter_predicate = filter_predicate.to_h.merge("provider" => previous)
  end

  # A `chat.message` trigger matches whichever messenger it names, so it must name one.
  def chat_provider_named
    provider = filter_predicate.to_h["provider"]
    return if provider.is_a?(String) && Chat::PROVIDERS.key?(provider)

    errors.add(:filter_predicate, "must name the messenger: provider is one of #{Chat::PROVIDERS.keys.join(', ')}")
  end

  # Whichever of the two the caller set wins and the other follows: the API, the
  # personal MCP and templates still write only notify_on_failure.
  def keep_failure_reporting_in_step
    silent = status_reporting.to_s == "none"
    if will_save_change_to_status_reporting? && !will_save_change_to_notify_on_failure?
      self.notify_on_failure = !silent
    elsif will_save_change_to_notify_on_failure? && !will_save_change_to_status_reporting?
      self.status_reporting = notify_on_failure ? (silent ? "failures" : status_reporting) : "none"
    end
  end

  def chat_text_command
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
