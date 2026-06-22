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

  enumerize :trigger_mode, in: %i[auto manual], default: :auto, predicates: true

  validates :event_type, presence: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project

  scope :active, -> { where(enabled: true) }
  scope :for_event, ->(event) { active.where(project_id: event.project_id, event_type: event.event_type) }

  # JSONB containment: does the event data satisfy every key/value of the
  # predicate? Empty predicate ⇒ matches any event of this type.
  def matches?(data)
    filter_predicate.all? { |key, value| data[key.to_s] == value }
  end

  private

  def workflow_accessible_from_project
    return unless workflow && project

    unless Workflow.visible_for_project(project).exists?(id: workflow_id)
      errors.add(:workflow, "must be accessible from this project")
    end
  end
end
