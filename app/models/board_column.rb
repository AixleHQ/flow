# frozen_string_literal: true

class BoardColumn < ApplicationRecord
  belongs_to :board
  has_one :column_workflow_binding, dependent: :destroy
  has_many :board_tasks, dependent: :restrict_with_error
  has_many :from_column_transitions, class_name: "ColumnTransition", foreign_key: :from_column_id, dependent: :destroy, inverse_of: :from_column
  has_many :to_column_transitions, class_name: "ColumnTransition", foreign_key: :to_column_id, dependent: :destroy, inverse_of: :to_column

  validates :name, presence: true
  validates :position, presence: true, uniqueness: { scope: :board_id }

  # Total active tasks per column, as a `tasks_count` attribute on each row. The board
  # header shows the real total while the column itself holds only the pages it has
  # loaded, so the count cannot come from the task payload — and a count per column
  # would be an N+1, hence the single GROUP BY.
  scope :with_tasks_count, -> {
    select("board_columns.*, COUNT(board_tasks.id) AS tasks_count")
      .joins(
        "LEFT OUTER JOIN board_tasks ON board_tasks.board_column_id = board_columns.id " \
        "AND board_tasks.archived_at IS NULL"
      )
      .group("board_columns.id")
  }

  before_validation :assign_next_position, on: :create
  after_save :detach_preset
  after_destroy :detach_preset
  after_commit :touch_board

  def self.ransackable_attributes(_auth_object = nil)
    %w[name position purpose created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[board]
  end

  private

  def touch_board
    board.touch if board&.persisted?
  end

  def assign_next_position
    return if position.present?

    self.position = (board&.board_columns&.maximum(:position).to_i) + 1
  end

  def detach_preset
    board.update_column(:preset_origin, nil) if board&.persisted? && board.preset_origin.present?
  end
end
