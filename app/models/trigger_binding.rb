# frozen_string_literal: true

# Generalized "events matching X start workflow Y" rule for event sources beyond
# the two legacy ones (column moves, task waits). A binding is matched against a
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

  validates :event_type, presence: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project
  validate :create_task_requires_column

  scope :active, -> { where(enabled: true) }
  scope :for_event, ->(event) { active.where(project_id: event.project_id, event_type: event.event_type) }

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
end
