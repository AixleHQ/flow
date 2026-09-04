# frozen_string_literal: true

class ColumnWorkflowBinding < ApplicationRecord
  extend Enumerize

  belongs_to :board_column
  belongs_to :workflow

  enumerize :trigger_mode, in: %i[auto manual], default: :manual, predicates: true

  validates :board_column_id, uniqueness: true
  validates :cooldown_seconds, numericality: { greater_than_or_equal_to: 0 }
  validate :workflow_accessible_from_project

  after_commit :touch_board

  private

  def touch_board
    # Skip when the board is already gone (e.g. project/board cascade destroy).
    # Matches BoardColumn#touch_board / BoardTask#touch_board.
    board = board_column&.board
    board.touch if board&.persisted?
  end

  def workflow_accessible_from_project
    return unless workflow && board_column

    project = board_column.board&.project
    return unless project

    unless Workflow.visible_for_project(project).exists?(id: workflow_id)
      errors.add(:workflow, "must be accessible from this project")
    end
  end
end
