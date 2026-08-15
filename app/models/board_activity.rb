# frozen_string_literal: true

class BoardActivity < ApplicationRecord
  extend Enumerize

  belongs_to :board
  belongs_to :board_task, optional: true
  belongs_to :actor, class_name: "User"

  enumerize :event_type, in: %i[
    task_created task_updated task_deleted task_moved
    task_archived task_unarchived
    comment_added asset_attached
    workflow_started workflow_completed workflow_failed workflow_cancelled
    human_help_requested
  ]
  enumerize :actor_type, in: %i[human agent system]

  validates :event_type, :actor_type, presence: true

  scope :for_board, ->(board) { where(board: board) }
  scope :for_task, ->(task) { where(board_task: task) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :by_actor_type, ->(type) { where(actor_type: type) }
  scope :since, ->(timestamp) { where("created_at >= ?", timestamp) }

  def self.timestamp_attributes_for_update
    []
  end
end
